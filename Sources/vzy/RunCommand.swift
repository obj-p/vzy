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

        // Fast path: the touch refreshes the LRU signal the sweep reads.
        // ANY launch failure — missing, evicted, or a corrupt entry —
        // falls through to a rebuild, which republishes a freshly signed
        // binary (repairing corruption); a real environmental failure
        // then surfaces on the post-build launch instead.
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: binary.path
        )
        do {
            if let status = try Self.launch(binary, arguments: scriptArgs) {
                Darwin.exit(status)
            }
        } catch {}

        try Self.buildAndPublish(
            binary: binary, cacheRoot: cacheRoot, source: source,
            manifest: manifest, entitlements: entitlements
        )

        guard let status = try Self.launch(binary, arguments: scriptArgs) else {
            throw RunError(message: "binary vanished after publish: \(binary.path)")
        }
        Darwin.exit(status)
    }

    /// Build the script in the shared package and publish the signed
    /// binary by atomic rename. Serializes on `.build.lock`, which is
    /// released when this returns — before the caller execs, so a script
    /// holding a VM for minutes never blocks other builds. The lock also
    /// makes this the one safe place to sweep the cache.
    static func buildAndPublish(
        binary: URL, cacheRoot: URL, source: String, manifest: String, entitlements: URL
    ) throws {
        let packageDir = cacheRoot.appending(path: "package")
        let stagingDir = cacheRoot.appending(path: "staging")
        let binDir = cacheRoot.appending(path: "bin")
        for dir in [stagingDir, binDir] {
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
        defer { flock(lockFd, LOCK_UN) }

        sweepCache(cacheRoot: cacheRoot, binDir: binDir, stagingDir: stagingDir)

        // Re-check under the lock: a queued waiter for the same script
        // finds the binary its predecessor just published.
        guard !FileManager.default.fileExists(atPath: binary.path) else { return }

        try synthesizePackage(at: packageDir, source: source, manifest: manifest)
        try sh("/usr/bin/swift", ["build", "-c", "release", "--package-path", packageDir.path])
        let builtDir = try capture(
            "/usr/bin/swift",
            ["build", "-c", "release", "--package-path", packageDir.path, "--show-bin-path"]
        )
        let built = URL(filePath: builtDir).appending(path: "vzscript")
        let staged = stagingDir.appending(path: UUID().uuidString)
        // After a successful rename the staged path no longer exists, so
        // this only cleans up when copy/codesign/rename failed.
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: built, to: staged)
        try sh(
            "/usr/bin/codesign",
            ["--force", "--sign", "-", "--entitlements", entitlements.path, staged.path]
        )
        guard rename(staged.path, binary.path) == 0 else {
            throw RunError(message: "could not publish \(binary.path): errno=\(errno)")
        }
    }

    static let binaryMaxAge: TimeInterval = 30 * 24 * 3600
    static let stagingMaxAge: TimeInterval = 3600

    /// Housekeeping, callable only under the build lock: evict script
    /// binaries unused for `binaryMaxAge` (each fast-path use refreshes
    /// mtime), remove staging leftovers from crashed builds, and clear
    /// the entries the pre-`package/` cache layout left at top level.
    /// Deletions are allowlisted by name — never "everything unknown" —
    /// so future additions to the cache root are safe from the sweep.
    static func sweepCache(cacheRoot: URL, binDir: URL, stagingDir: URL) {
        sweep(binDir, olderThan: binaryMaxAge)
        sweep(stagingDir, olderThan: stagingMaxAge)
        for legacy in ["Package.swift", "Package.resolved", "Sources", ".build"] {
            try? FileManager.default.removeItem(at: cacheRoot.appending(path: legacy))
        }
    }

    private static func sweep(_ dir: URL, olderThan maxAge: TimeInterval) {
        let fm = FileManager.default
        for entry in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
            let url = dir.appending(path: entry)
            guard let mtime = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                  Date().timeIntervalSince(mtime) > maxAge else { continue }
            try? fm.removeItem(at: url)
        }
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
        hasher.update(data: Data(toolchainIdentity().utf8))
        hasher.update(data: try read(entitlements))
        hasher.update(data: try read(packageRoot.appending(path: "Package.swift")))
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
                hasher.update(data: try read(file))
            }
        }
        return String(hasher.finalize().hexString.prefix(32))
    }

    /// Active developer dir plus its Xcode version stamp, without
    /// spawning a toolchain subprocess (which would tax the fast path).
    /// A toolchain upgrade must invalidate cached binaries — the old
    /// always-run `swift build` got that from SPM for free. Best-effort:
    /// a CLT-only setup has no version.plist, and a missing stamp just
    /// means path-only identity, as before this existed.
    private static func toolchainIdentity() -> String {
        let developerDir = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
            ?? (try? FileManager.default.destinationOfSymbolicLink(
                atPath: "/var/db/xcode_select_link"
            ))
            ?? ""
        let versionPlist = URL(filePath: developerDir)
            .deletingLastPathComponent()
            .appending(path: "version.plist")
        let stamp = (try? Data(contentsOf: versionPlist)) ?? Data()
        return developerDir + ":" + stamp.hexString
    }

    /// Cache-key inputs must read successfully — substituting empty data
    /// would compute a colliding key and serve a stale binary.
    private static func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw RunError(
                message: "could not read cache-key input \(url.path): \(error.localizedDescription)"
            )
        }
    }

    /// Run `binary` to completion, returning its exit status. Returns nil
    /// only when the binary is missing (the caller rebuilds); any other
    /// launch failure is thrown rather than masked as a cache miss.
    static func launch(_ binary: URL, arguments: [String]) throws -> Int32? {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            let ns = error as NSError
            let missing = (ns.domain == NSCocoaErrorDomain
                && (ns.code == NSFileNoSuchFileError || ns.code == NSFileReadNoSuchFileError))
                || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
            if missing {
                return nil
            }
            throw error
        }
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            return 128 + process.terminationStatus
        }
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
        guard process.terminationStatus == 0 else {
            throw RunError(
                message: "\(path) \(args.joined(separator: " ")) exited \(process.terminationStatus)"
            )
        }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
