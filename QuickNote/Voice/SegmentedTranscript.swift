import Foundation

/// The text of a voice recording that is recognized in several requests ("segments"), because Apple
/// caps the length of each one. Every segment keeps its own text, in the order it was spoken, until its
/// recognizer has said its last word. A segment that was handed over to the next one keeps updating
/// until then, and a finished segment waits behind an unfinished one, so words are neither dropped nor
/// repeated at the seams.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct SegmentedTranscript {
    private struct Segment {
        let generation: Int
        /// Words the recognizer forgot after a long pause (see `receive`), kept in front of its new text.
        var kept = ""
        /// The recognizer's current transcription of this segment.
        var heard = ""
        /// When the last word of the latest result with usable timestamps ends, in seconds into the segment.
        var endsAt: TimeInterval?
        /// The recognizer has said its last word (or failed; the latest text is then kept).
        var isDone = false

        var text: String { SegmentedTranscript.join([kept, heard]) }
    }

    private var committed: [String] = []
    private var segments: [Segment] = []
    private var currentGeneration: Int?

    /// Whether the segment that last said its last word had heard any text.
    private(set) var lastEndedHeardText = false

    /// Starts a new segment, the one now receiving audio. Earlier segments may still be finishing.
    mutating func begin(generation: Int) {
        segments.append(Segment(generation: generation))
        currentGeneration = generation
    }

    /// Feeds in what a recognizer reported. `text` is its whole transcription of the segment so far
    /// (nil if it has none), `startsAt` and `endsAt` the times its first word begins and its last word
    /// ends, and `isLast` says it is done with this segment, whether by a final result or by failing.
    /// Returns true when this closed the segment that is receiving audio.
    ///
    /// Unknown and already finished segments are ignored, and an empty result never overwrites text
    /// that was heard. On some systems a result after a pause contains only the words since the pause.
    /// That shows as a first word starting at or after the end of the previous result's last word (a
    /// revised word starts before that end), so the earlier text is kept in front. Timestamps that are
    /// all zero are not trusted. If the recognizer later gives the earlier words again, the kept text
    /// is dropped so they aren't said twice.
    @discardableResult
    mutating func receive(
        generation: Int,
        text: String?,
        startsAt: TimeInterval?,
        endsAt: TimeInterval?,
        isLast: Bool
    ) -> Bool {
        guard let index = segments.firstIndex(where: { $0.generation == generation }),
              !segments[index].isDone
        else { return false }

        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hasTimes = (endsAt ?? 0) > 0
            if !segments[index].kept.isEmpty, Self.words(text).starts(with: Self.words(segments[index].kept)) {
                segments[index].kept = ""
            } else if hasTimes, let startsAt, let previousEnd = segments[index].endsAt, previousEnd > 0,
                      startsAt >= previousEnd {
                segments[index].kept = segments[index].text
            }
            segments[index].heard = text
            if hasTimes { segments[index].endsAt = endsAt }
        }
        guard isLast else { return false }

        segments[index].isDone = true
        lastEndedHeardText = !segments[index].text.isEmpty
        let closedCurrent = generation == currentGeneration
        while let first = segments.first, first.isDone {
            if !first.text.isEmpty { committed.append(first.text) }
            segments.removeFirst()
        }
        return closedCurrent
    }

    /// Everything heard so far, finished and unfinished segments in speaking order, joined by a space.
    var text: String {
        Self.join(committed + segments.map(\.text))
    }

    /// Whether some segment hasn't said its last word yet.
    var hasPending: Bool {
        segments.contains { !$0.isDone }
    }

    /// Lowercased words without punctuation, to compare texts the recognizer worded slightly differently.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func join(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
