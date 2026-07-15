import Testing
@testable import VZKit

struct SetupAssistantSequenceTests {
    @Test func shiftedSymbolsMapToUnshiftedBaseKeys() {
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "&") == 0x37)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "!") == 0x31)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "?") == 0x2F)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "_") == 0x2D)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "\"") == 0x27)
    }

    @Test func uppercaseLettersMapToLowercaseBase() {
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "A") == UInt32(UnicodeScalar("a").value))
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "Z") == UInt32(UnicodeScalar("z").value))
    }

    @Test func unshiftedCharactersNeedNoShiftSynthesis() {
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "a") == nil)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "7") == nil)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: "-") == nil)
        #expect(SetupAssistantSequence.shiftedAsciiBase(for: " ") == nil)
    }

    @Test func everyKeyHasANonZeroKeysym() {
        for key in KeyboardScripter.Key.allCases {
            #expect(SetupAssistantSequence.keysym(for: key) != 0, "unmapped key: \(key)")
        }
    }
}
