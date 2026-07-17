import CryptoKit
import Foundation
import Virtualization

/// IPSW resolution + on-disk cache.
///
/// Apple ships restore images as `.ipsw` files at multi-GB URLs on the
/// CDN. The cache lives at `~/.cache/vz/ipsw/<layout-version>/`. A
/// queryless URL is keyed by a hash of its scheme, host, port, and
/// path plus its basename — instant and offline-capable, and distinct
/// URLs sharing a filename can't collide. A query-bearing URL is
/// ambiguous (the query may be an expiring ticket or a file selector,
/// issue #3), so it resolves content-addressed instead: a HEAD request
/// reads the digest S3-backed CDNs advertise and the entry lives at
/// `sha256:<digest>.ipsw` (tart's mechanism). A host that advertises
/// no digest falls back to a query-inclusive key, accepting
/// re-downloads over ever serving the wrong bytes.
///
/// Three input shapes resolve to a local IPSW file:
///
///   - **Local path** (`/foo/restore.ipsw`): used verbatim, no download.
///   - **HTTPS URL**: downloaded to the cache, returned.
///   - **`nil`** (no `--ipsw` flag): `VZMacOSRestoreImage.fetchLatestSupported`
///     is consulted, the resulting CDN URL is downloaded.
public enum IPSWStore {
    /// Cache layout version, encoded as the subdirectory all entries live
    /// under. Bump when key derivation or entry naming changes: a new
    /// version simply writes to a fresh directory and
    /// `prepareCacheDirectory` clears stale version dirs — no marker file
    /// whose absence is ambiguous, and deleting the directory is always
    /// safe (worst case: re-download).
    static let cacheLayoutVersion = "v1"

    static var cacheBaseDirectory: URL {
        let base = (ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            .map { URL(filePath: $0) })
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".cache")
        return base.appending(path: "vz/ipsw")
    }

    /// Directory where downloaded IPSWs are cached.
    public static var cacheDirectory: URL {
        cacheBaseDirectory.appending(path: cacheLayoutVersion)
    }

    public enum Source: Sendable {
        case localFile(URL)
        case remoteURL(URL)
        case latestSupported
    }

    /// Resolve `source` to a local IPSW file, downloading + caching if
    /// necessary. Prints periodic progress to stderr.
    public static func resolve(_ source: Source) async throws -> URL {
        switch source {
        case let .localFile(url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw VMError("IPSW does not exist at \(url.path)")
            }
            return url

        case let .remoteURL(url):
            return try await downloadRemote(url)

        case .latestSupported:
            Log.info("looking up latest supported macOS restore image…")
            let image: VZMacOSRestoreImage
            do {
                image = try await fetchLatestRestoreImage()
            } catch {
                throw VMError("VZMacOSRestoreImage.fetchLatestSupported failed", underlying: error)
            }
            Log.info("latest supported: macOS \(image.operatingSystemVersion) (\(image.buildVersion))")
            return try await downloadRemote(image.url)
        }
    }

    /// Bridge `VZMacOSRestoreImage.fetchLatestSupported(completionHandler:)`
    /// (Result-based, completion-handler only) to async/await.
    ///
    /// Why the box: `VZMacOSRestoreImage` is not `Sendable`, so passing it
    /// directly through a `CheckedContinuation` trips Swift 6's
    /// SendingRisksDataRace check. The image is read-only and Apple's
    /// callbacks deliver it exactly once on an internal queue, so wrapping
    /// in an `@unchecked Sendable` carrier is safe — we just unwrap on
    /// the caller's actor.
    private static func fetchLatestRestoreImage() async throws -> VZMacOSRestoreImage {
        let box: RestoreImageBox = try await withCheckedThrowingContinuation { cont in
            VZMacOSRestoreImage.fetchLatestSupported { result in
                switch result {
                case let .success(image): cont.resume(returning: RestoreImageBox(image))
                case let .failure(error): cont.resume(throwing: error)
                }
            }
        }
        return box.image
    }

    /// Bridge `VZMacOSRestoreImage.load(from:completionHandler:)`. Used by
    /// `BundleProvisioner` and any future caller that needs the parsed
    /// restore-image metadata.
    public static func loadRestoreImage(at url: URL) async throws -> VZMacOSRestoreImage {
        let box: RestoreImageBox = try await withCheckedThrowingContinuation { cont in
            VZMacOSRestoreImage.load(from: url) { result in
                switch result {
                case let .success(image): cont.resume(returning: RestoreImageBox(image))
                case let .failure(error): cont.resume(throwing: error)
                }
            }
        }
        return box.image
    }

    /// Convenience: `resolve` from a CLI string. Empty/nil → latest;
    /// `https://…` → remote; anything else → local path.
    public static func resolve(_ flag: String?) async throws -> URL {
        guard let raw = flag, !raw.isEmpty else {
            return try await resolve(.latestSupported)
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            guard let url = URL(string: raw), url.host() != nil else {
                throw VMError("not a valid URL: \(raw)")
            }
            return try await resolve(.remoteURL(url))
        }
        let expanded = (raw as NSString).expandingTildeInPath
        let url = if expanded.hasPrefix("/") {
            URL(filePath: expanded)
        } else {
            URL(filePath: FileManager.default.currentDirectoryPath)
                .appending(path: expanded)
        }
        return try await resolve(.localFile(url))
    }

    /// `<cacheDirectory>/<sha256 prefix>-<basename>`. The hash keeps
    /// distinct URLs that share a filename from colliding in the cache.
    /// It covers scheme, host, port, and path; the query joins only when
    /// `includeQuery` is set (the no-digest fallback for query URLs) so
    /// a rotating signed-URL token still hits the cache by default.
    static func cacheDestination(for remote: URL, includeQuery: Bool = false) throws -> URL {
        let filename = remote.lastPathComponent
        guard !filename.isEmpty, filename != "/" else {
            throw VMError("URL has no IPSW filename to cache under: \(remote.absoluteString)")
        }
        var key = "\(remote.scheme ?? "")://\(remote.host() ?? ""):\(remote.port ?? -1)\(remote.path())"
        if includeQuery {
            key += "?\(remote.query ?? "")"
        }
        let prefix = SHA256.hash(data: Data(key.utf8)).hexString.prefix(12)
        return cacheDirectory.appending(path: "\(prefix)-\(filename)")
    }

    /// Create the current layout's directory and clear what older layouts
    /// left behind: stale `vN` version dirs, and the pre-versioned
    /// top-level entries (`*.ipsw` files and the `cache-version` marker).
    /// Deletions are allowlisted by shape — unknown entries are preserved.
    static func prepareCacheDirectory(in base: URL = cacheBaseDirectory) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: base.appending(path: cacheLayoutVersion), withIntermediateDirectories: true
        )
        for entry in (try? fm.contentsOfDirectory(atPath: base.path)) ?? [] {
            let url = base.appending(path: entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let staleVersionDir = isDir.boolValue
                && entry != cacheLayoutVersion
                && entry.wholeMatch(of: /v[0-9]+/) != nil
            let legacyEntry = !isDir.boolValue
                && (entry.hasSuffix(".ipsw") || entry == "cache-version")
            if staleVersionDir || legacyEntry {
                Log.info("clearing stale IPSW cache entry \(url.path)")
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Throw unless the download response is a success. `URLSession.download`
    /// only throws on transport errors, so without this a 404/403 error body
    /// would be cached as the IPSW.
    static func validateDownloadResponse(_ response: URLResponse, from remote: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw VMError(
                "IPSW download from \(remote.absoluteString) failed: HTTP \(http.statusCode)"
            )
        }
    }

    /// Route a remote URL to the right cache strategy: queryless URLs
    /// use the URL key (offline-capable); query URLs resolve
    /// content-addressed via the advertised digest, falling back to a
    /// query-inclusive key when the host advertises none.
    private static func downloadRemote(_ remote: URL) async throws -> URL {
        try prepareCacheDirectory()
        guard remote.query != nil else {
            return try await downloadIfNeeded(
                remote: remote, destination: cacheDestination(for: remote)
            )
        }
        guard let digest = await advertisedDigest(for: remote) else {
            return try await downloadIfNeeded(
                remote: remote, destination: cacheDestination(for: remote, includeQuery: true)
            )
        }
        let destination = cacheDirectory.appending(path: "sha256:\(digest).ipsw")
        if FileManager.default.fileExists(atPath: destination.path) {
            Log.info("using cached IPSW at \(destination.path)")
            return destination
        }
        let temp = try await downloadToTemporary(remote: remote)
        let computed = try sha256OfFile(temp)
        if computed != digest {
            Log.info("advertised digest \(digest) != downloaded \(computed); storing by downloaded")
        }
        let final = cacheDirectory.appending(path: "sha256:\(computed).ipsw")
        try place(temp, at: final)
        Log.info("download complete: \(final.path)")
        return final
    }

    /// HEAD the URL and return the content digest S3-backed CDNs advertise
    /// (the same header tart reads). nil when the host doesn't send it or
    /// the probe fails — callers fall back to a query-inclusive URL key.
    private static func advertisedDigest(for remote: URL) async -> String? {
        var request = URLRequest(url: remote)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode)
        else {
            return nil
        }
        return http.value(forHTTPHeaderField: "x-amz-meta-digest-sha256")?.lowercased()
    }

    /// Streaming SHA256 of a file on disk — cache entries are multi-GB,
    /// so never load one into memory whole.
    static func sha256OfFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }

    private static func downloadIfNeeded(remote: URL, destination: URL) async throws -> URL {
        if FileManager.default.fileExists(atPath: destination.path) {
            Log.info("using cached IPSW at \(destination.path)")
            return destination
        }
        let temp = try await downloadToTemporary(remote: remote)
        try place(temp, at: destination)
        Log.info("download complete: \(destination.path)")
        return destination
    }

    private static func downloadToTemporary(remote: URL) async throws -> URL {
        Log.info("downloading IPSW from \(remote.absoluteString)")
        Log.info("  (multi-GB; this can take a long time on a slow link)")

        let reporter = DownloadProgressReporter()
        let session = URLSession(
            configuration: .default,
            delegate: reporter,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        let progressTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                reporter.logProgress()
            }
        }
        defer { progressTask.cancel() }

        let temp: URL
        let response: URLResponse
        do {
            (temp, response) = try await session.download(from: remote)
        } catch {
            throw VMError("IPSW download failed", underlying: error)
        }
        do {
            try validateDownloadResponse(response, from: remote)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        return temp
    }

    /// URLSession's "temp" file is unlinked when the next download
    /// begins, so atomic-move it into the cache before returning.
    private static func place(_ temp: URL, at destination: URL) throws {
        do {
            try FileManager.default.moveItem(at: temp, to: destination)
        } catch {
            // The temp may sit in /tmp; copy then delete as a fallback
            // in case `moveItem` trips over a cross-volume rename.
            do {
                try FileManager.default.copyItem(at: temp, to: destination)
                try? FileManager.default.removeItem(at: temp)
            } catch {
                throw VMError("could not place IPSW into cache", underlying: error)
            }
        }
    }
}

/// `VZMacOSRestoreImage` is read-only and Apple's APIs deliver it once
/// on an internal queue. Wrapping it lets us pass through a
/// `CheckedContinuation` under Swift 6 strict concurrency.
private final class RestoreImageBox: @unchecked Sendable {
    let image: VZMacOSRestoreImage
    init(_ image: VZMacOSRestoreImage) {
        self.image = image
    }
}

/// `URLSessionDownloadDelegate` that records cumulative byte counts.
/// `IPSWStore.downloadToTemporary` spawns a separate Task that
/// periodically reads this reporter and emits a stderr line.
private final class DownloadProgressReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var bytesWritten: Int64 = 0
    private var totalBytesExpected: Int64 = 0
    private var lastLoggedPercent: Int = -1

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        defer { lock.unlock() }
        bytesWritten = totalBytesWritten
        totalBytesExpected = totalBytesExpectedToWrite
    }

    func urlSession(
        _: URLSession,
        downloadTask _: URLSessionDownloadTask,
        didFinishDownloadingTo _: URL
    ) {
        // No-op — URLSession.download(from:) handles the temp file for us.
    }

    func logProgress() {
        lock.lock()
        let got = bytesWritten
        let total = totalBytesExpected
        lock.unlock()
        guard total > 0 else {
            if got > 0 {
                Log.info("download in progress (\(got / 1024 / 1024) MiB, total size unknown yet)")
            }
            return
        }
        let percent = Int(Double(got) / Double(total) * 100)
        if percent != lastLoggedPercent {
            lock.lock()
            lastLoggedPercent = percent
            lock.unlock()
            Log.info("download: \(percent)% (\(got / 1024 / 1024) / \(total / 1024 / 1024) MiB)")
        }
    }
}
