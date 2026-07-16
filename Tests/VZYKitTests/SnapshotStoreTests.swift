import Foundation
import Testing
@testable import VZYKit

struct SnapshotStoreTests {
    func withRunnableBundle(_ body: (VMBundle) throws -> Void) throws {
        try BundleFixture.withBundle { bundle in
            try Data("disk-A".utf8).write(to: bundle.diskImageURL)
            try Data("aux-A".utf8).write(to: bundle.auxStorageURL)
            try body(bundle)
        }
    }

    @Test(arguments: ["", "a/b", "..", "."])
    func rejectsIllegalNames(name: String) throws {
        try withRunnableBundle { bundle in
            #expect(throws: VMError.self) {
                try SnapshotStore.take(name: name, of: bundle)
            }
            #expect(throws: VMError.self) {
                try SnapshotStore.delete(name: name, in: bundle)
            }
        }
    }

    @Test func takeListRestoreDeleteRoundTrip() throws {
        try withRunnableBundle { bundle in
            let snapshot = try SnapshotStore.take(name: "base", of: bundle)
            #expect(snapshot.name == "base")
            let listed = try SnapshotStore.list(in: bundle)
            #expect(listed.map(\.name) == ["base"])

            try Data("disk-B".utf8).write(to: bundle.diskImageURL)
            try SnapshotStore.restore(name: "base", in: bundle)
            let disk = try Data(contentsOf: bundle.diskImageURL)
            let aux = try Data(contentsOf: bundle.auxStorageURL)
            #expect(disk == Data("disk-A".utf8))
            #expect(aux == Data("aux-A".utf8))

            try SnapshotStore.delete(name: "base", in: bundle)
            let afterDelete = try SnapshotStore.list(in: bundle)
            #expect(afterDelete.isEmpty)
        }
    }

    @Test func takeRefusesDuplicateName() throws {
        try withRunnableBundle { bundle in
            _ = try SnapshotStore.take(name: "base", of: bundle)
            #expect(throws: VMError.self) {
                try SnapshotStore.take(name: "base", of: bundle)
            }
        }
    }

    @Test func takeRefusesWhileVMRunning() throws {
        try withRunnableBundle { bundle in
            try VMPidFile.write(getpid(), to: bundle)
            #expect(throws: VMError.self) {
                try SnapshotStore.take(name: "base", of: bundle)
            }
            #expect(throws: VMError.self) {
                try SnapshotStore.restore(name: "base", in: bundle)
            }
        }
    }

    @Test func restoreMissingSnapshotThrows() throws {
        try withRunnableBundle { bundle in
            #expect(throws: VMError.self) {
                try SnapshotStore.restore(name: "nope", in: bundle)
            }
        }
    }

    @Test func listReturnsEmptyWithoutSnapshotsDirectory() throws {
        try withRunnableBundle { bundle in
            let listed = try SnapshotStore.list(in: bundle)
            #expect(listed.isEmpty)
        }
    }
}
