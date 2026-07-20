import Foundation
import Testing
@testable import VZYKit

struct IPSWStoreTests {
    @Test func resolvesExistingLocalPath() async throws {
        let file = FileManager.default.temporaryDirectory
            .appending(path: "vzy-test-\(UUID().uuidString).ipsw")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)

        let resolved = try await IPSWStore.resolve(file.path)
        #expect(resolved.path == file.path)
    }

    @Test func throwsForMissingLocalPath() async {
        await #expect(throws: VMError.self) {
            try await IPSWStore.resolve("/nonexistent/restore.ipsw")
        }
    }

    @Test func throwsForInvalidURLString() async {
        await #expect(throws: VMError.self) {
            try await IPSWStore.resolve("https://bad host/restore.ipsw")
        }
    }

    @Test func throwsForURLWithoutHost() async {
        await #expect(throws: VMError.self) {
            try await IPSWStore.resolve("https://")
        }
    }

    @Test func throwsForURLWithoutFilename() async {
        await #expect(throws: VMError.self) {
            try await IPSWStore.resolve("https://example.com")
        }
        await #expect(throws: VMError.self) {
            try await IPSWStore.resolve("https://example.com/")
        }
    }

    @Test func remoteURLSourceWithoutFilenameThrowsBeforeTouchingCache() async throws {
        let url = try #require(URL(string: "https://example.com/"))
        await #expect(throws: VMError.self) {
            try await IPSWStore.resolve(.remoteURL(url))
        }
    }

    @Test func cacheDestinationDiffersForSameFilenameOnDifferentHosts() throws {
        let a = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://host-a/restore.ipsw"))
        )
        let b = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://host-b/restore.ipsw"))
        )
        #expect(a != b)
        #expect(a.lastPathComponent.hasSuffix("-restore.ipsw"))
        #expect(b.lastPathComponent.hasSuffix("-restore.ipsw"))
    }

    @Test func cacheDestinationIsStableForTheSameURL() throws {
        let url = try #require(URL(string: "https://example.com/restore.ipsw"))
        #expect(
            try IPSWStore.cacheDestination(for: url)
                == IPSWStore.cacheDestination(for: url)
        )
    }

    @Test func cacheDestinationDiffersByScheme() throws {
        let secure = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://cdn.example.com/restore.ipsw"))
        )
        let insecure = try IPSWStore.cacheDestination(
            for: #require(URL(string: "http://cdn.example.com/restore.ipsw"))
        )
        #expect(secure != insecure)
    }

    @Test func cacheDestinationIgnoresQueryAndFragment() throws {
        let tokenA = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://cdn.example.com/restore.ipsw?token=aaa"))
        )
        let tokenB = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://cdn.example.com/restore.ipsw?token=bbb#frag"))
        )
        let bare = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://cdn.example.com/restore.ipsw"))
        )
        #expect(tokenA == bare)
        #expect(tokenB == bare)
    }

    @Test func prepareClearsLegacyShapesAndPreservesUnknowns() throws {
        try BundleFixture.withDirectory { base in
            let fm = FileManager.default
            try Data("old".utf8).write(to: base.appending(path: "restore.ipsw"))
            try Data("2".utf8).write(to: base.appending(path: "cache-version"))
            try Data("mine".utf8).write(to: base.appending(path: "user-notes.txt"))
            try fm.createDirectory(at: base.appending(path: "v0"), withIntermediateDirectories: true)
            try fm.createDirectory(at: base.appending(path: "other-dir"), withIntermediateDirectories: true)

            try IPSWStore.prepareCacheDirectory(in: base)

            #expect(fm.fileExists(atPath: base.appending(path: IPSWStore.cacheLayoutVersion).path))
            #expect(!fm.fileExists(atPath: base.appending(path: "restore.ipsw").path))
            #expect(!fm.fileExists(atPath: base.appending(path: "cache-version").path))
            #expect(!fm.fileExists(atPath: base.appending(path: "v0").path))
            #expect(fm.fileExists(atPath: base.appending(path: "user-notes.txt").path))
            #expect(fm.fileExists(atPath: base.appending(path: "other-dir").path))
        }
    }

    @Test func prepareKeepsCurrentVersionContents() throws {
        try BundleFixture.withDirectory { base in
            let entry = base.appending(path: "\(IPSWStore.cacheLayoutVersion)/abc-restore.ipsw")
            try FileManager.default.createDirectory(
                at: entry.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("cached".utf8).write(to: entry)
            try IPSWStore.prepareCacheDirectory(in: base)
            #expect(FileManager.default.fileExists(atPath: entry.path))
        }
    }

    @Test func queryInclusiveKeyDiffersByQuery() throws {
        let tokenA = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://cdn.example.com/restore.ipsw?build=23A")),
            includeQuery: true
        )
        let tokenB = try IPSWStore.cacheDestination(
            for: #require(URL(string: "https://cdn.example.com/restore.ipsw?build=24B")),
            includeQuery: true
        )
        #expect(tokenA != tokenB)
    }

    @Test func sha256OfFileMatchesKnownDigest() throws {
        try BundleFixture.withDirectory { dir in
            let file = dir.appending(path: "hello.bin")
            try Data("hello".utf8).write(to: file)
            #expect(
                try IPSWStore.sha256OfFile(file)
                    == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
            )
        }
    }

    @Test func cacheDestinationThrowsWithoutFilename() throws {
        let url = try #require(URL(string: "https://example.com/"))
        #expect(throws: VMError.self) {
            try IPSWStore.cacheDestination(for: url)
        }
    }

    @Test func non2xxDownloadResponseIsRejected() throws {
        let url = try #require(URL(string: "https://example.com/restore.ipsw"))
        let notFound = try #require(
            HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
        )
        #expect(throws: VMError.self) {
            try IPSWStore.validateDownloadResponse(notFound, from: url)
        }
    }

    @Test func successfulDownloadResponseIsAccepted() throws {
        let url = try #require(URL(string: "https://example.com/restore.ipsw"))
        let ok = try #require(
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        )
        try IPSWStore.validateDownloadResponse(ok, from: url)
        try IPSWStore.validateDownloadResponse(URLResponse(), from: url)
    }
}
