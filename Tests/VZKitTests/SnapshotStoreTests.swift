import Foundation
import Testing
@testable import VZKit

struct SnapshotStoreTests {
    func makeRunnableBundle() throws -> VMBundle {
        let bundle = try BundleFixture.makeBundle()
        try Data("disk-A".utf8).write(to: bundle.diskImageURL)
        try Data("aux-A".utf8).write(to: bundle.auxStorageURL)
        return bundle
    }

    @Test(arguments: ["", "a/b", "..", "."])
    func rejectsIllegalNames(name: String) throws {
        let bundle = try makeRunnableBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(throws: VMError.self) {
            try SnapshotStore.take(name: name, of: bundle)
        }
        #expect(throws: VMError.self) {
            try SnapshotStore.delete(name: name, in: bundle)
        }
    }

    @Test func takeListRestoreDeleteRoundTrip() throws {
        let bundle = try makeRunnableBundle()
        defer { BundleFixture.remove(bundle) }

        let snapshot = try SnapshotStore.take(name: "base", of: bundle)
        #expect(snapshot.name == "base")
        #expect(try SnapshotStore.list(in: bundle).map(\.name) == ["base"])

        try Data("disk-B".utf8).write(to: bundle.diskImageURL)
        try SnapshotStore.restore(name: "base", in: bundle)
        #expect(try Data(contentsOf: bundle.diskImageURL) == Data("disk-A".utf8))
        #expect(try Data(contentsOf: bundle.auxStorageURL) == Data("aux-A".utf8))

        try SnapshotStore.delete(name: "base", in: bundle)
        #expect(try SnapshotStore.list(in: bundle).isEmpty)
    }

    @Test func takeRefusesDuplicateName() throws {
        let bundle = try makeRunnableBundle()
        defer { BundleFixture.remove(bundle) }
        _ = try SnapshotStore.take(name: "base", of: bundle)
        #expect(throws: VMError.self) {
            try SnapshotStore.take(name: "base", of: bundle)
        }
    }

    @Test func takeRefusesWhileVMRunning() throws {
        let bundle = try makeRunnableBundle()
        defer { BundleFixture.remove(bundle) }
        try VMPidFile.write(getpid(), to: bundle)
        #expect(throws: VMError.self) {
            try SnapshotStore.take(name: "base", of: bundle)
        }
        #expect(throws: VMError.self) {
            try SnapshotStore.restore(name: "base", in: bundle)
        }
    }

    @Test func restoreMissingSnapshotThrows() throws {
        let bundle = try makeRunnableBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(throws: VMError.self) {
            try SnapshotStore.restore(name: "nope", in: bundle)
        }
    }

    @Test func listReturnsEmptyWithoutSnapshotsDirectory() throws {
        let bundle = try makeRunnableBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(try SnapshotStore.list(in: bundle).isEmpty)
    }
}
