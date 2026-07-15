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
        try BundleFixture.withDirectory { dir in
            #expect(throws: VMError.self) {
                try VMBundle(directory: dir)
            }
        }
    }

    @Test func throwsWhenConfigMalformed() throws {
        try BundleFixture.withDirectory { dir in
            try Data("{\"cpuCount\": 4}".utf8).write(to: dir.appending(path: "config.json"))
            #expect(throws: VMError.self) {
                try VMBundle(directory: dir)
            }
        }
    }

    @Test func decodesConfig() throws {
        try BundleFixture.withBundle { bundle in
            #expect(bundle.config.cpuCount == 4)
            #expect(bundle.config.memorySizeBytes == 8_589_934_592)
            #expect(bundle.config.macAddress == "52:54:00:12:34:56")
            #expect(bundle.config.sshUsername == "admin")
        }
    }

    @Test func sshKeyURLsFollowConfiguredKeyName() throws {
        try BundleFixture.withBundle { bundle in
            #expect(bundle.sshPrivateKeyURL.lastPathComponent == "id_ed25519")
            #expect(bundle.sshPublicKeyURL.lastPathComponent == "id_ed25519.pub")
        }
    }

    @Test func requireRunnableThrowsWhenFilesMissing() throws {
        try BundleFixture.withBundle { bundle in
            #expect(throws: VMError.self) {
                try bundle.requireRunnable()
            }
        }
    }

    @Test func requireRunnablePassesWhenAllFilesPresent() throws {
        try BundleFixture.withBundle { bundle in
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
}
