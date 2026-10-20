import AppKit

/// Listens to the keyboard system-wide and calls `onTrigger` when ⌃⌥ is tapped on its own, and
/// `onRecord` for ⌃⌥R. Events are only observed, never consumed, so every key still reaches the
/// frontmost app. The one exception is ⌃⌥R inside QuickNote itself, which is kept out of the text views.
@MainActor
final class HotkeyMonitor {
    private var detector = ModifierChordDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onTrigger: @MainActor () -> Void
    private let onRecord: @MainActor () -> Void

    init(onTrigger: @escaping @MainActor () -> Void, onRecord: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
        self.onRecord = onRecord
    }

    /// Keys pressed in other apps. Requires the Accessibility permission, so call this only once it
    /// has been granted. Calling it again replaces the monitor: one added before the permission was
    /// turned off may not hear anything once it's back on.
    func startGlobal() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.events) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.handle(event) }
        }
    }

    /// Keys pressed while QuickNote itself is frontmost, including in the capture panel, where the
    /// same chord saves and closes it.
    func startLocal() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.events) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) } ?? false
            return consumed ? nil : event
        }
    }

    /// Clicks count like key presses: ⌃⌥-click and ⌃⌥-drag are shortcuts too.
    private static let events: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// Returns true if the event was ⌃⌥R (repeats included). Only the local monitor can act on that (by dropping the event);
    /// a global monitor can't consume events.
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            detector.keyPressed()
        case .keyDown:
            // First, so that any key cancels a ⌃⌥ tap in progress, ⌃⌥R included.
            detector.keyPressed()
            let held = ModifierKeys(event.modifierFlags)
            let key = event.charactersIgnoringModifiers
            guard RecordShortcut.isShortcut(held: held, key: key) else { return false }
            // Holding the keys down repeats the key press: dropped, but it must not toggle again.
            if RecordShortcut.matches(held: held, key: key, isRepeat: event.isARepeat) {
                onRecord()
            }
            return true
        case .flagsChanged:
            if detector.modifiersChanged(to: ModifierKeys(event.modifierFlags), at: event.timestamp) {
                onTrigger()
            }
        default:
            break
        }
        return false
    }
}

private extension ModifierKeys {
    /// Caps Lock and fn are ignored: fn is set by arrow and function keys, which also send a keyDown.
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }
}
