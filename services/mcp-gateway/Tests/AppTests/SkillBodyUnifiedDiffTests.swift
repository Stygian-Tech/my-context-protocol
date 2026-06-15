import Testing
@testable import App

@Suite("SkillBodyUnifiedDiff")
struct SkillBodyUnifiedDiffTests {
    @Test func identicalTextsReturnNil() {
        let text = "line1\nline2\n"
        let out = SkillBodyUnifiedDiff.format(oldText: text, newText: text)
        #expect(out == nil)
    }

    @Test func lineChangeProducesUnifiedMarkers() {
        let oldText = "alpha\nbeta\ngamma\n"
        let newText = "alpha\nBETA\ngamma\n"
        guard let out = SkillBodyUnifiedDiff.format(oldText: oldText, newText: newText) else {
            Issue.record("expected non-nil diff")
            return
        }
        #expect(out.contains("-beta"))
        #expect(out.contains("+BETA"))
    }
}
