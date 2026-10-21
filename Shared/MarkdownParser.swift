import Foundation

/// Styles that apply to a run of words, written as marks on both sides.
enum InlineStyle: CaseIterable, Sendable {
    case bold, italic, strike, highlight

    /// The mark the toolbar and keyboard shortcuts write on each side of the selection.
    /// Italic uses `_` so bold italic reads `**_like this_**` rather than an ambiguous `***`.
    var mark: String {
        switch self {
        case .bold: "**"
        case .italic: "_"
        case .strike: "~~"
        case .highlight: "=="
        }
    }
}

/// What a whole line is, set by a mark at its start.
enum LineKind: Equatable, Sendable {
    case text
    case title
    case bullet
    case todo(done: Bool)

    /// The mark written at the start of a line to make it this kind.
    var prefix: String {
        switch self {
        case .text: ""
        case .title: "# "
        case .bullet: "- "
        case .todo(let done): done ? "[x] " : "[ ] "
        }
    }

    /// Same kind, ignoring whether a to-do is done.
    func isSameKind(as other: LineKind) -> Bool {
        switch (self, other) {
        case (.text, .text), (.title, .title), (.bullet, .bullet), (.todo, .todo): true
        default: false
        }
    }
}

struct MarkdownLine: Equatable {
    /// The whole line, without its line break.
    var range: NSRange
    var kind: LineKind
    /// The mark at the start, including its trailing space. Empty for plain text.
    var markRange: NSRange
    var contentRange: NSRange
}

struct InlineSpan: Equatable {
    var style: InlineStyle
    /// Marks included.
    var range: NSRange
    var contentRange: NSRange
    var openMark: NSRange
    var closeMark: NSRange
}

/// A small subset of Markdown: `#` titles, `-` bullets, `[ ]` to-dos, and `**bold**`, `_italic_`
/// (or `*italic*`), `~~strike~~` and `==highlight==`. Ranges are UTF-16, as NSString and
/// NSTextView use them.
enum MarkdownParser {
    // Line marks, tried in order.
    private static let todo = try! NSRegularExpression(pattern: #"^(?:[-*] )?\[([ xX])\] "#)
    private static let title = try! NSRegularExpression(pattern: #"^#{1,3} "#)
    private static let bullet = try! NSRegularExpression(pattern: #"^[-*•] "#)

    // Inline styles: the content must start and end with a non-space character.
    private static let inline: [(InlineStyle, NSRegularExpression, Int)] = [
        (.bold, try! NSRegularExpression(pattern: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#), 2),
        (.strike, try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#), 2),
        (.highlight, try! NSRegularExpression(pattern: #"==(?=\S)(.+?)(?<=\S)=="#), 2),
        (.italic, try! NSRegularExpression(pattern: #"(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])"#), 1),
        (.italic, try! NSRegularExpression(pattern: #"(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])"#), 1),
    ]

    static func lines(in text: String) -> [MarkdownLine] {
        let string = text as NSString
        var result: [MarkdownLine] = []
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            result.append(line(in: string, range: range))
        }
        // A trailing line break starts an empty last line the enumeration doesn't report.
        if string.length > 0, string.hasSuffix("\n") {
            result.append(MarkdownLine(range: NSRange(location: string.length, length: 0), kind: .text, markRange: NSRange(location: string.length, length: 0), contentRange: NSRange(location: string.length, length: 0)))
        }
        return result
    }

    static func spans(in text: String, lines: [MarkdownLine]) -> [InlineSpan] {
        var result: [InlineSpan] = []
        for line in lines where line.contentRange.length > 0 {
            for (style, regex, markLength) in inline {
                regex.enumerateMatches(in: text, range: line.contentRange) { match, _, _ in
                    guard let match else { return }
                    let content = match.range(at: 1)
                    result.append(InlineSpan(
                        style: style,
                        range: match.range,
                        contentRange: content,
                        openMark: NSRange(location: match.range.location, length: markLength),
                        closeMark: NSRange(location: NSMaxRange(content), length: markLength)
                    ))
                }
            }
        }
        return result
    }

    /// The line with its marks removed, for titles and previews in lists.
    static func plainText(_ line: String) -> String {
        let parsed = self.line(in: line as NSString, range: NSRange(location: 0, length: (line as NSString).length))
        var text = (line as NSString).substring(with: parsed.contentRange)
        for (_, regex, _) in inline {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "$1")
        }
        return text
    }

    private static func line(in string: NSString, range: NSRange) -> MarkdownLine {
        let text = string as String
        let start = NSRange(location: range.location, length: 0)
        func make(_ kind: LineKind, _ mark: NSRange) -> MarkdownLine {
            MarkdownLine(range: range, kind: kind, markRange: mark, contentRange: NSRange(location: NSMaxRange(mark), length: NSMaxRange(range) - NSMaxRange(mark)))
        }
        if let match = todo.firstMatch(in: text, options: .anchored, range: range) {
            let done = string.substring(with: match.range(at: 1)) != " "
            return make(.todo(done: done), match.range)
        }
        if let match = title.firstMatch(in: text, options: .anchored, range: range) {
            return make(.title, match.range)
        }
        if let match = bullet.firstMatch(in: text, options: .anchored, range: range) {
            return make(.bullet, match.range)
        }
        return make(.text, start)
    }
}
