import Foundation

extension String {
    /// The end of a long text, for showing what was said last: at most about `maxLength` characters,
    /// cut at a word boundary and starting with "…". Short texts are returned as they are.
    ///
    /// Pure logic with no AppKit dependency so it can be unit tested.
    func endingExcerpt(maxLength: Int = 90) -> String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxLength else { return text }

        var tail = text.suffix(maxLength)
        // If the cut fell inside a word, drop the rest of that word.
        let cutInsideWord = !text[text.index(tail.startIndex, offsetBy: -1)].isWhitespace
        if cutInsideWord, let space = tail.firstIndex(where: \.isWhitespace) {
            tail = tail[space...]
        }
        return "… " + tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
