import Foundation
import Testing
@testable import VZKit

struct VMBundleTests {
    @Test func throwsWhenDirectoryMissing() {
        #expect(throws: VMError.self) {
            try VMBundle(directory: URL(filePath: "/nonexistent/bundle"))
        }
    }

    @Test func throwsWhenConfigMissing() throws {
        let dir = try BundleFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: VMError.self) {
            try VMBundle(directory: dir)
        }
    }

    @Test func throwsWhenConfigMalformed() throws {
        let dir = try BundleFixture.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("{\"cpuCount\": 4}".utf8).write(to: dir.appending(path: "config.json"))
        #expect(throws: VMError.self) {
            try VMBundle(directory: dir)
        }
    }

    @Test func decodesConfig() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(bundle.config.cpuCount == 4)
        #expect(bundle.config.memorySizeBytes == 8_589_934_592)
        #expect(bundle.config.macAddress == "52:54:00:12:34:56")
        #expect(bundle.config.sshUsername == "admin")
    }

    @Test func sshKeyURLsFollowConfiguredKeyName() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(bundle.sshPrivateKeyURL.lastPathComponent == "id_ed25519")
        #expect(bundle.sshPublicKeyURL.lastPathComponent == "id_ed25519.pub")
    }

    @Test func requireRunnableThrowsWhenFilesMissing() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(throws: VMError.self) {
            try bundle.requireRunnable()
        }
    }

    @Test func requireRunnablePassesWhenAllFilesPresent() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        for url in [
            bundle.diskImageURL, bundle.auxStorageURL,
            bundle.machineIdentifierURL, bundle.hardwareModelURL,
            bundle.sshPrivateKeyURL,
        ] {
            try Data().write(to: url)
        }
        try bundle.requireRunnable()
    }
}
