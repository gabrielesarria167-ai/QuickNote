import Foundation
import Testing
@testable import QuickNote

struct MarkdownParserTests {
    private func kinds(_ text: String) -> [LineKind] {
        MarkdownParser.lines(in: text).map(\.kind)
    }

    private func spans(_ text: String) -> [(InlineStyle, String)] {
        let lines = MarkdownParser.lines(in: text)
        return MarkdownParser.spans(in: text, lines: lines).map { ($0.style, (text as NSString).substring(with: $0.contentRange)) }
    }

    @Test func lineKinds() {
        let text = "# Bike rack\nHangs on the wall\n- Hinge at the base\n[ ] Ask the store\n[x] Measure\n- [ ] Also a to-do"
        #expect(kinds(text) == [.title, .text, .bullet, .todo(done: false), .todo(done: true), .todo(done: false)])
    }

    @Test func markRangesCoverThePrefix() {
        let line = MarkdownParser.lines(in: "[ ] Ask the store")[0]
        #expect(line.markRange == NSRange(location: 0, length: 4))
        #expect(line.contentRange == NSRange(location: 4, length: 13))
    }

    @Test func aDashWithoutSpaceIsText() {
        #expect(kinds("-5 degrees\n#hashtag") == [.text, .text])
    }

    @Test func trailingLineBreakAddsAnEmptyLine() {
        #expect(MarkdownParser.lines(in: "- one\n").count == 2)
    }

    @Test func inlineStyles() {
        let found = spans("A **bold** and _italic_ and *also italic*, ~~gone~~ and ==marked==.")
        #expect(found.map(\.0) == [.bold, .strike, .highlight, .italic, .italic])
        #expect(found.map(\.1) == ["bold", "gone", "marked", "italic", "also italic"])
    }

    @Test func nestedBoldItalic() {
        let found = spans("**_both_**")
        #expect(found.map(\.0) == [.bold, .italic])
        #expect(found.map(\.1) == ["_both_", "both"])
    }

    @Test func notStylesInOrdinaryText() {
        #expect(spans("2 * 3 * 4, snake_case_name, a ** b").isEmpty)
    }

    @Test func spanMarkRanges() {
        let span = MarkdownParser.spans(in: "x **y**", lines: MarkdownParser.lines(in: "x **y**"))[0]
        #expect(span.openMark == NSRange(location: 2, length: 2))
        #expect(span.closeMark == NSRange(location: 5, length: 2))
    }

    @Test func plainTextStripsMarks() {
        #expect(MarkdownParser.plainText("# Bike **rack** that _folds_") == "Bike rack that folds")
        #expect(MarkdownParser.plainText("[x] ==Measure== the hall") == "Measure the hall")
    }
}
