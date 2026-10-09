import Foundation

/// The global shortcut that starts and stops a voice recording: ⌃⌥R.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum RecordShortcut {
    static let modifiers: ModifierKeys = [.control, .option]

    /// `key` is the character without modifiers applied (layout-aware), so ⌥ doesn't turn it into "®".
    /// Held-down key repeats don't count, or one long press would start and stop the recording.
    static func matches(held: ModifierKeys, key: String?, isRepeat: Bool) -> Bool {
        held == modifiers && key?.lowercased() == "r" && !isRepeat
    }
}
