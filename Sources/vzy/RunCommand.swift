import ArgumentParser
import CryptoKit
import Darwin
import Foundation
import VZKit

struct RunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Compile, codesign, and run a Swift script against VZKit."
    )

    @Argument(parsing: .captureForPassthrough, help: "Script path, then args passed to it.")
    var items: [String] = []

    struct RunError: Error, CustomStringConvertible {
        let message: String
        var description: String {
            message
        }
    }

    /// Script binaries are cached content-addressed: `bin/<key>`, where the
    /// key hashes the script source, the VZKit/VZKitObjC source closure,
    /// the entitlements, and the build recipe. An unchanged script re-runs
    /// instantly — no build, no lock — and published binaries are immutable,
    /// so concurrent runs (same or different scripts) can never execute each
    /// other's code. Cache misses serialize on `.build.lock` in the shared
    /// package (one VZKit compile per install, incremental after) and
    /// publish by atomic rename of a signed staging copy.
    func run() throws {
        guard let scriptPath = items.first else {
            throw ValidationError("usage: vzy run <script.swift> [args…]")
        }
        let scriptArgs = Array(items.dropFirst())
        let source = try String(contentsOf: URL(filePath: scriptPath), encoding: .utf8)

        let packageRoot = Self.packageRoot
        let entitlements = packageRoot.appending(path: "Resources/vzy.entitlements")
        let manifest = Self.manifest(packageRoot: packageRoot)

        let rootHash = SHA256.hash(data: Data(packageRoot.path.utf8)).hexString.prefix(16)
        let cacheRoot = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache/vz-run/\(rootHash)")
        let key = try Self.cacheKey(
            source: source, manifest: manifest,
            entitlements: entitlements, packageRoot: packageRoot
        )
        let binary = cacheRoot.appending(path: "bin/\(key)")

        // Fast path. A launch failure (evicted between check and exec)
        // falls through to a rebuild.
        if FileManager.default.fileExists(atPath: binary.path),
           let status = Self.launch(binary, arguments: scriptArgs) {
            Darwin.exit(status)
        }

        let packageDir = cacheRoot.appending(path: "package")
        let stagingDir = cacheRoot.appending(path: "staging")
        for dir in [packageDir, stagingDir, cacheRoot.appending(path: "bin")] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let lockFd = open(
            cacheRoot.appending(path: ".build.lock").path,
            O_CREAT | O_RDWR | O_CLOEXEC, 0o644
        )
        guard lockFd >= 0 else {
            throw RunError(message: "could not open build lock in \(cacheRoot.path)")
        }
        defer { close(lockFd) }
        while flock(lockFd, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw RunError(message: "flock failed: errno=\(errno)")
            }
        }

        // Re-check under the lock: a queued waiter for the same script
        // finds the binary its predecessor just published.
        if !FileManager.default.fileExists(atPath: binary.path) {
            try Self.synthesizePackage(at: packageDir, source: source, manifest: manifest)
            try Self.sh("/usr/bin/swift", ["build", "-c", "release", "--package-path", packageDir.path])
            let binDir = try Self.capture(
                "/usr/bin/swift",
                ["build", "-c", "release", "--package-path", packageDir.path, "--show-bin-path"]
            )
            let built = URL(filePath: binDir).appending(path: "vzscript")
            let staged = stagingDir.appending(path: UUID().uuidString)
            try FileManager.default.copyItem(at: built, to: staged)
            try Self.sh(
                "/usr/bin/codesign",
                ["--force", "--sign", "-", "--entitlements", entitlements.path, staged.path]
            )
            guard rename(staged.path, binary.path) == 0 else {
                throw RunError(message: "could not publish \(binary.path): errno=\(errno)")
            }
        }
        flock(lockFd, LOCK_UN) // release before exec — scripts may hold a VM for minutes

        guard let status = Self.launch(binary, arguments: scriptArgs) else {
            throw RunError(message: "could not launch \(binary.path)")
        }
        Darwin.exit(status)
    }

    /// The VZKit package the script compiles against. A Homebrew install
    /// keeps the package sources beside the binary's real file (libexec),
    /// so a manifest next to the executable wins; otherwise this is a dev
    /// build and `#filePath` points into the checkout.
    static var packageRoot: URL {
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let adjacent = executable.deletingLastPathComponent()
            if FileManager.default.fileExists(
                atPath: adjacent.appending(path: "Package.swift").path
            ) {
                return adjacent
            }
        }
        return URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// Everything that determines the built binary's bytes: script source,
    /// synthesized manifest, build flags, entitlements, the package-root
    /// manifest, and every VZKit/VZKitObjC source file (headers included —
    /// a narrower closure would serve stale code after a library edit).
    static func cacheKey(
        source: String, manifest: String, entitlements: URL, packageRoot: URL
    ) throws -> String {
        var hasher = SHA256()
        hasher.update(data: Data(source.utf8))
        hasher.update(data: Data(manifest.utf8))
        hasher.update(data: Data("swift build -c release".utf8))
        hasher.update(data: (try? Data(contentsOf: entitlements)) ?? Data())
        hasher.update(
            data: (try? Data(contentsOf: packageRoot.appending(path: "Package.swift"))) ?? Data()
        )
        for target in ["Sources/VZKit", "Sources/VZKitObjC"] {
            let root = packageRoot.appending(path: target)
            let paths = (FileManager.default.enumerator(atPath: root.path)?
                .compactMap { $0 as? String } ?? []).sorted()
            for path in paths {
                let file = root.appending(path: path)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir),
                      !isDir.boolValue else { continue }
                hasher.update(data: Data("\(target)/\(path)".utf8))
                hasher.update(data: try Data(contentsOf: file))
            }
        }
        return String(hasher.finalize().hexString.prefix(32))
    }

    /// Run `binary` to completion. Returns nil if it could not be launched.
    static func launch(_ binary: URL, arguments: [String]) -> Int32? {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func manifest(packageRoot: URL) -> String {
        let escapedRoot = packageRoot.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        // swift-tools-version: 6.0
        import PackageDescription

        let package = Package(
            name: "vzscript",
            platforms: [.macOS(.v14)],
            dependencies: [.package(name: "vzy", path: "\(escapedRoot)")],
            targets: [
                .executableTarget(
                    name: "vzscript",
                    dependencies: [.product(name: "VZKit", package: "vzy")]
                )
            ]
        )
        """
    }

    static func synthesizePackage(at dir: URL, source: String, manifest: String) throws {
        let sourcesDir = dir.appending(path: "Sources/vzscript")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appending(path: "Package.swift"), atomically: true, encoding: .utf8)
        try source.write(
            to: sourcesDir.appending(path: "main.swift"), atomically: true, encoding: .utf8
        )
    }

    static func sh(_ path: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RunError(message: "\(path) \(args.joined(separator: " ")) exited \(process.terminationStatus)")
        }
    }

    static func capture(_ path: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
