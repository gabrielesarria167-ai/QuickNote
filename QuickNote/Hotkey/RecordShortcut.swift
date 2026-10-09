import Foundation

/// The global shortcut that starts and stops a voice recording: ⌃⌥R.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum RecordShortcut {
    static let modifiers: ModifierKeys = [.control, .option]

    /// Whether this key press is ⌃⌥R, held-down repeats included, so QuickNote can keep those out of
    /// its text views. `key` is the character without modifiers applied (layout-aware), so ⌥ doesn't
    /// turn it into "®".
    static func isShortcut(held: ModifierKeys, key: String?) -> Bool {
        held == modifiers && key?.lowercased() == "r"
    }

    /// Whether this key press should start or stop a recording. Repeats don't count, or one long press
    /// would start and stop it.
    static func matches(held: ModifierKeys, key: String?, isRepeat: Bool) -> Bool {
        isShortcut(held: held, key: key) && !isRepeat
    }
}
