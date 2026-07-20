import Foundation
@testable import VZYKit

enum BundleFixture {
    static let configJSON = """
    {
        "cpuCount": 4,
        "memorySizeBytes": 8589934592,
        "macAddress": "52:54:00:12:34:56",
        "sshUsername": "admin",
        "sshKeyName": "id_ed25519"
    }
    """

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "vzy-test-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    static func withBundle(_ body: (VMBundle) throws -> Void) throws {
        try withDirectory { dir in
            try Data(configJSON.utf8).write(to: dir.appending(path: "config.json"))
            try body(VMBundle(directory: dir))
        }
    }
}
