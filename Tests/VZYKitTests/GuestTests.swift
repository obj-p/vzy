import Testing
@testable import VZYKit

struct GuestTests {
    @Test func shellQuoteWrapsInSingleQuotes() {
        #expect(Guest.shellQuote("hello") == "'hello'")
        #expect(Guest.shellQuote("two words") == "'two words'")
    }

    @Test func shellQuoteEscapesEmbeddedSingleQuotes() {
        #expect(Guest.shellQuote("it's") == "'it'\\''s'")
    }

    @Test func shellQuoteLeavesOtherShellMetacharactersInert() {
        #expect(Guest.shellQuote("$HOME; rm -rf *") == "'$HOME; rm -rf *'")
    }
}
