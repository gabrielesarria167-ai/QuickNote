import Foundation

/// Builds up the text of a voice recording that is recognized in several requests (Apple caps the
/// length of each one). Finished requests become committed segments; the request still running
/// has a partial that is replaced every time the recognizer reports again.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct TranscriptAccumulator {
    private var committed: [String] = []
    private var partial = ""

    /// Replaces the in-flight partial. Recognizers re-send the whole best transcription so far.
    mutating func update(partial: String) {
        self.partial = partial
    }

    /// Ends the in-flight request: commits `final` if given (the recognizer's last word on it),
    /// otherwise the current partial. Blank text is dropped.
    mutating func commitSegment(final: String? = nil) {
        let segment = (final ?? partial).trimmingCharacters(in: .whitespacesAndNewlines)
        if !segment.isEmpty {
            committed.append(segment)
        }
        partial = ""
    }

    /// Everything heard so far, segments joined by a single space.
    var text: String {
        (committed + [partial])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var isEmpty: Bool { text.isEmpty }

    /// Adds a transcript to the end of a note as a new paragraph.
    static func appending(_ transcript: String, to existing: String) -> String {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return existing }
        guard !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return transcript }
        var base = existing
        while let last = base.last, last.isWhitespace {
            base.removeLast()
        }
        return base + "\n\n" + transcript
    }
}
