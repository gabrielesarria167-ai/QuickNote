import Foundation

/// Detects two character keys pressed at the same time, e.g. `.` and `-`, without getting in the
/// way of typing them one at a time.
///
/// A press of either key is held back for `window` seconds. If the other key goes down in that
/// time it's a chord: both are swallowed, and so are their repeats and releases. Otherwise the
/// held press is let through (`flush…`), late by at most `window`.
///
/// Pure logic with no AppKit dependency so it can be unit tested; the caller keeps the actual
/// held event and acts on each `Decision`.
struct KeyChordDetector {
    enum Decision: Equatable {
        /// Not ours: deliver it.
        case pass
        /// Keep this press back until the other key or a timeout decides.
        case hold
        /// Deliver the press held earlier, then hold this one.
        case flushThenHold
        /// Deliver the press held earlier, then this one.
        case flushThenPass
        /// The chord: drop the held press and this one.
        case chord
        /// Part of a chord already recognised: drop it.
        case swallow
    }

    var keys: Set<String> = [".", "-"]
    var window: TimeInterval = 0.07

    /// Changes every time a press is held, so a timeout for an older one is ignored.
    private(set) var generation = 0
    private var held: (key: String, at: TimeInterval)?
    private var chordKeys: Set<String> = []

    /// - Parameter hasShortcutModifier: ⌘, ⌃ or ⌥ is held, so this is a shortcut, never the chord.
    mutating func keyDown(_ characters: String?, at timestamp: TimeInterval, isRepeat: Bool, hasShortcutModifier: Bool) -> Decision {
        guard let key = characters, keys.contains(key), !hasShortcutModifier else {
            return releaseHeld() ? .flushThenPass : .pass
        }
        if chordKeys.contains(key) {
            return .swallow
        }
        if isRepeat {
            return releaseHeld() ? .flushThenPass : .pass
        }
        if let held, held.key != key, timestamp - held.at <= window {
            self.held = nil
            chordKeys = [held.key, key]
            return .chord
        }
        let hadHeld = held != nil
        held = (key, timestamp)
        generation += 1
        return hadHeld ? .flushThenHold : .hold
    }

    mutating func keyUp(_ characters: String?) -> Decision {
        if let key = characters, chordKeys.remove(key) != nil {
            return .swallow
        }
        return releaseHeld() ? .flushThenPass : .pass
    }

    /// Call `window` after a `.hold`. Returns `true` when that press is still held back and should
    /// now be delivered.
    mutating func timedOut(generation: Int) -> Bool {
        guard generation == self.generation, held != nil else { return false }
        held = nil
        return true
    }

    private mutating func releaseHeld() -> Bool {
        guard held != nil else { return false }
        held = nil
        return true
    }
}
