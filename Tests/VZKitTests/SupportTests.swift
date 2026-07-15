import Foundation
import Testing
@testable import VZKit

struct SupportTests {
    @Test func hexStringEncodesBytesAsLowercasePairs() {
        #expect(Data([0x00, 0x0F, 0xAB]).hexString == "000fab")
        #expect("A".utf8.hexString == "41")
        #expect(Data().hexString == "")
    }
}
