import Foundation

/// The modifier keys a chord can be made of.
struct ModifierKeys: OptionSet, Hashable {
    let rawValue: UInt8

    static let control = ModifierKeys(rawValue: 1 << 0)
    static let option = ModifierKeys(rawValue: 1 << 1)
    static let shift = ModifierKeys(rawValue: 1 << 2)
    static let command = ModifierKeys(rawValue: 1 << 3)
}

/// Detects a chord of modifier keys tapped on their own, e.g. ⌃⌥: pressed together and released
/// with no other key in between. Shortcuts that start with the same modifiers (⌃⌥→, VoiceOver's
/// ⌃⌥ commands) never count, because a key is pressed while they're held.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct ModifierChordDetector {
    var chord: ModifierKeys = [.control, .option]
    /// Longest time from the first modifier going down to all of them being released.
    var maxDuration: TimeInterval = 0.8

    private var startedAt: TimeInterval?
    private var reachedChord = false
    private var cancelled = false

    /// Feed every change of the held modifiers. Returns `true` when the last one is released and
    /// completes a tap of the chord.
    mutating func modifiersChanged(to held: ModifierKeys, at timestamp: TimeInterval) -> Bool {
        guard !held.isEmpty else {
            defer { reset() }
            guard let startedAt, reachedChord, !cancelled else { return false }
            return timestamp - startedAt <= maxDuration
        }
        if startedAt == nil {
            startedAt = timestamp
        }
        if held == chord {
            reachedChord = true
        } else if !chord.isSuperset(of: held) {
            // Another modifier joined in, e.g. ⌃⌥⌘.
            cancelled = true
        }
        return false
    }

    /// Feed every key press: pressing a key while the modifiers are held makes it a shortcut.
    mutating func keyPressed() {
        if startedAt != nil {
            cancelled = true
        }
    }

    private mutating func reset() {
        startedAt = nil
        reachedChord = false
        cancelled = false
    }
}
