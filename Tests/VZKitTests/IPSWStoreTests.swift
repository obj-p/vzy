import Foundation
import Testing
@testable import VZKit

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
