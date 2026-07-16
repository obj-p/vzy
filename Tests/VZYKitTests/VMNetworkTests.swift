import Foundation
import Testing
@testable import VZYKit

struct VMNetworkTests {
    let stanza = """
    {
    \tname=guest-host
    \tip_address=192.168.64.42
    \thw_address=1,52:54:0:12:34:56
    \tidentifier=1,52:54:0:12:34:56
    \tlease=0x67200000
    }
    """

    @Test func parsesSingleLease() {
        let leases = VMNetwork.parseLeases(stanza)
        #expect(leases == [
            VMNetwork.Lease(
                name: "guest-host",
                ipAddress: "192.168.64.42",
                macAddress: "52:54:0:12:34:56"
            ),
        ])
    }

    @Test func parsesMultipleStanzas() {
        let text = """
        {
        \tip_address=192.168.64.10
        \thw_address=1,aa:bb:cc:dd:ee:ff
        }
        {
        \tip_address=192.168.64.11
        \thw_address=1,11:22:33:44:55:66
        }
        """
        let leases = VMNetwork.parseLeases(text)
        #expect(leases.count == 2)
        #expect(leases[0].ipAddress == "192.168.64.10")
        #expect(leases[1].macAddress == "11:22:33:44:55:66")
    }

    @Test func nameIsOptional() {
        let text = """
        {
        \tip_address=192.168.64.10
        \thw_address=1,aa:bb:cc:dd:ee:ff
        }
        """
        #expect(VMNetwork.parseLeases(text).first?.name == nil)
    }

    @Test func skipsStanzaMissingIPOrMAC() {
        let text = """
        {
        \tname=no-ip
        \thw_address=1,aa:bb:cc:dd:ee:ff
        }
        {
        \tname=no-mac
        \tip_address=192.168.64.10
        }
        """
        #expect(VMNetwork.parseLeases(text).isEmpty)
    }

    @Test func macWithoutHtypePrefixIsKept() {
        let text = """
        {
        \tip_address=192.168.64.10
        \thw_address=aa:bb:cc:dd:ee:ff
        }
        """
        #expect(VMNetwork.parseLeases(text).first?.macAddress == "aa:bb:cc:dd:ee:ff")
    }

    @Test func ignoresGarbageLines() {
        let text = """
        junk line
        {
        \tip_address=192.168.64.10
        \thw_address=1,aa:bb:cc:dd:ee:ff
        \tnot a key value pair
        }
        trailing junk
        """
        #expect(VMNetwork.parseLeases(text).count == 1)
    }

    @Test func normalizePadsAndLowercases() {
        #expect(VMNetwork.normalize("52:54:0:1:2:3") == "52:54:00:01:02:03")
        #expect(VMNetwork.normalize("AA:BB:0:12:34:56") == "aa:bb:00:12:34:56")
        #expect(VMNetwork.normalize("52:54:00:12:34:56") == "52:54:00:12:34:56")
    }

    @Test func ipAddressMatchesUnpaddedLeaseAgainstPaddedConfigMAC() throws {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "vzy-test-leases-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        try stanza.write(toFile: path, atomically: true, encoding: .utf8)

        #expect(
            VMNetwork.ipAddress(forMAC: "52:54:00:12:34:56", leasesPath: path)
                == "192.168.64.42"
        )
        #expect(VMNetwork.ipAddress(forMAC: "52:54:00:99:99:99", leasesPath: path) == nil)
    }

    @Test func ipAddressReturnsNilWhenLeasesFileMissing() {
        #expect(
            VMNetwork.ipAddress(
                forMAC: "52:54:00:12:34:56",
                leasesPath: "/nonexistent/dhcpd_leases"
            ) == nil
        )
    }
}
