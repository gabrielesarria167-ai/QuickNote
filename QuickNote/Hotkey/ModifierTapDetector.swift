import Foundation

/// Detects a modifier key being tapped on its own: pressed and released
/// quickly with no other key in between. Holding it to type a capital letter
/// doesn't count.
struct ModifierTapDetector {
    /// Virtual key code of the modifier (60 = right Shift).
    var keyCode: UInt16 = 60
    var maxDuration: TimeInterval = 0.4

    private var pressedAt: TimeInterval?

    /// Feed every `flagsChanged` event. Returns `true` when the modifier is
    /// released and completes a tap.
    mutating func modifierChanged(keyCode: UInt16, isDown: Bool, timestamp: TimeInterval) -> Bool {
        guard keyCode == self.keyCode else {
            pressedAt = nil
            return false
        }
        if isDown {
            pressedAt = timestamp
            return false
        }
        defer { pressedAt = nil }
        guard let pressedAt else { return false }
        return timestamp - pressedAt <= maxDuration
    }

    /// Feed every `keyDown` event: typing while the modifier is held cancels the tap.
    mutating func keyPressed() {
        pressedAt = nil
    }
}
