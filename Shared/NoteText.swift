import Foundation

extension String {
    /// Adds a paragraph to the end of this note text. Trailing whitespace of the note is dropped, so
    /// exactly one blank line separates the two. A blank paragraph changes nothing.
    func appendingParagraph(_ paragraph: String) -> String {
        let paragraph = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { return self }
        guard !trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return paragraph }
        var base = self
        while let last = base.last, last.isWhitespace {
            base.removeLast()
        }
        return base + "\n\n" + paragraph
    }
}
