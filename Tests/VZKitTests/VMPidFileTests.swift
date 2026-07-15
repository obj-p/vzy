import Foundation
import Testing
@testable import VZKit

struct VMPidFileTests {
    @Test func writeReadRoundTrip() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        try VMPidFile.write(12345, to: bundle)
        #expect(VMPidFile.read(bundle) == 12345)
    }

    @Test func readReturnsNilWhenFileMissing() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        #expect(VMPidFile.read(bundle) == nil)
    }

    @Test func readReturnsNilForGarbageContent() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        try Data("not a pid\n".utf8).write(to: bundle.pidFileURL)
        #expect(VMPidFile.read(bundle) == nil)
    }

    @Test func clearRemovesFileAndTolerantOfMissing() throws {
        let bundle = try BundleFixture.makeBundle()
        defer { BundleFixture.remove(bundle) }
        try VMPidFile.write(12345, to: bundle)
        VMPidFile.clear(bundle)
        #expect(VMPidFile.read(bundle) == nil)
        VMPidFile.clear(bundle)
    }

    @Test func currentProcessIsAlive() {
        #expect(VMPidFile.isAlive(getpid()))
    }
}
