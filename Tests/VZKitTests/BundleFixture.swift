import Foundation
@testable import VZKit

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

    static func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "vzy-test-bundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func makeBundle() throws -> VMBundle {
        let dir = try makeDirectory()
        try Data(configJSON.utf8).write(to: dir.appending(path: "config.json"))
        return try VMBundle(directory: dir)
    }

    static func remove(_ bundle: VMBundle) {
        try? FileManager.default.removeItem(at: bundle.url)
    }
}
