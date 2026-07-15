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
}
