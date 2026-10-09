import Foundation

/// Builds the text a voice note is saved as: an optional title line, then the transcript.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum VoiceNoteText {
    /// The longest title kept, in characters.
    static let maxTitleLength = 80

    private static let lineMark = #"^(?:#{1,6}|>|[-*•]|\[[ xX]\])(?:\s+|$)"#
    /// Quotes stripped from either end on their own. Single quotes are left out: they double as
    /// apostrophes ("the dogs'"), so they only go as a pair.
    private static let quotes = CharacterSet(charactersIn: "\"`“”„«»「」『』")
    private static let endings = CharacterSet(charactersIn: ".。…").union(.whitespaces)
    private static let danglingPunctuation = CharacterSet(charactersIn: ",;:-–—.。…").union(.whitespaces)

    /// A model-written title made safe to put in a note: its first non-blank line, without line marks
    /// (`#`, bullets, `[ ]`, `>`), inline marks (`**bold**`), surrounding quotes or a trailing period,
    /// cut at a word boundary if longer than `maxTitleLength`. Nil if nothing is left.
    static func sanitizeTitle(_ title: String?) -> String? {
        guard let title,
              let firstLine = title.split(whereSeparator: \.isNewline)
                  .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }

        var text = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var previous: String
        repeat {
            previous = text
            text = text.replacingOccurrences(of: lineMark, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: quotes.union(.whitespaces))
            text = strippingSingleQuotePair(text)
            text = trimmingEnd(text, of: endings.union(quotes))
        } while text != previous
        text = trimmingEnd(MarkdownParser.plainText(text), of: endings.union(quotes))
        text = text.trimmingCharacters(in: quotes.union(.whitespaces))

        if text.count > maxTitleLength {
            let head = text.prefix(maxTitleLength)
            let atWordEnd = text[head.endIndex].isWhitespace
            if !atWordEnd, let space = head.lastIndex(where: \.isWhitespace) {
                text = String(head[..<space])
            } else {
                text = String(head)
            }
            text = trimmingEnd(text, of: danglingPunctuation)
        }
        return text.isEmpty ? nil : text
    }

    /// The note text for a transcript: `# Title` on its own line above it, or just the transcript
    /// when there is no usable title. A blank transcript gives an empty string, whatever the title.
    static func compose(title: String?, transcript: String) -> String {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return "" }
        guard let title = sanitizeTitle(title) else { return transcript }
        return "# \(title)\n\(transcript)"
    }

    /// The text without a single quote at both ends ('like this' or ‘like this’); one on its own stays.
    private static func strippingSingleQuotePair(_ text: String) -> String {
        guard text.count > 1, let first = text.first, let last = text.last,
              "'‘’".contains(first), "'’‘".contains(last)
        else { return text }
        return String(text.dropFirst().dropLast())
    }

    private static func trimmingEnd(_ text: String, of set: CharacterSet) -> String {
        var result = Substring(text)
        while let last = result.last, last.unicodeScalars.allSatisfy(set.contains) {
            result.removeLast()
        }
        return String(result)
    }
}
