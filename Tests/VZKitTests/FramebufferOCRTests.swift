import CoreGraphics
import Testing
@testable import VZKit

struct FramebufferOCRTests {
    func obs(_ text: String, x: CGFloat = 0, y: CGFloat = 0) -> FramebufferOCR.Observation {
        FramebufferOCR.Observation(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: 100, height: 20)
        )
    }

    @Test func exactMatchBeatsLongerSubstringMatch() {
        let observations = [obs("Disagree"), obs("Agree")]
        #expect(FramebufferOCR.find("Agree", in: observations)?.text == "Agree")
    }

    @Test func fallsBackToSubstringMatch() {
        let observations = [obs("Continue with Touch ID")]
        #expect(FramebufferOCR.find("Continue", in: observations)?.text == "Continue with Touch ID")
    }

    @Test func matchIsCaseInsensitiveByDefault() {
        let observations = [obs("CONTINUE")]
        #expect(FramebufferOCR.find("continue", in: observations) != nil)
    }

    @Test func caseSensitiveMatchRespectsCase() {
        let observations = [obs("CONTINUE")]
        #expect(FramebufferOCR.find("continue", in: observations, caseInsensitive: false) == nil)
        #expect(FramebufferOCR.find("CONTINUE", in: observations, caseInsensitive: false) != nil)
    }

    @Test func returnsNilWhenTextAbsent() {
        let observations = [obs("Disagree"), obs("Skip")]
        #expect(FramebufferOCR.find("Accept", in: observations) == nil)
    }

    @Test func prefersCenterMostAmongDuplicates() {
        let size = CGSize(width: 1280, height: 720)
        let corner = obs("Continue", x: 0, y: 0)
        let center = obs("Continue", x: 590, y: 350)
        let found = FramebufferOCR.find(
            "Continue", in: [corner, center], framebufferSize: size
        )
        #expect(found == center)
    }

    @Test func withoutFramebufferSizeReturnsFirstMatch() {
        let corner = obs("Continue", x: 0, y: 0)
        let center = obs("Continue", x: 590, y: 350)
        #expect(FramebufferOCR.find("Continue", in: [corner, center]) == corner)
    }

    @Test func centerIsBoundingBoxMidpoint() {
        let o = obs("x", x: 100, y: 200)
        #expect(o.center == CGPoint(x: 150, y: 210))
    }
}
