import Foundation

/// A button that only acts on its second press within a short time, so a stray click can't throw
/// away something that can't be recovered.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct ConfirmPress {
    /// How long the first press stays armed, in seconds.
    var window: TimeInterval = 3

    private var armedAt: TimeInterval?

    /// Returns true if this press confirms an earlier one; otherwise arms the button and returns false.
    mutating func press(at now: TimeInterval) -> Bool {
        if let armedAt, now - armedAt <= window {
            self.armedAt = nil
            return true
        }
        armedAt = now
        return false
    }

    /// Forgets the first press.
    mutating func reset() {
        armedAt = nil
    }
}
