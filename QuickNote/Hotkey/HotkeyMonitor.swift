import AppKit

/// Listens to the keyboard system-wide and calls `onTrigger` when ⌃⌥ is tapped on its own.
/// Events are only observed, never consumed, so every key still reaches the frontmost app.
@MainActor
final class HotkeyMonitor {
    private var detector = ModifierChordDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onTrigger: @MainActor () -> Void

    init(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
    }

    /// Keys pressed in other apps. Requires the Accessibility permission, so call this only once it
    /// has been granted.
    func startGlobal() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    /// Keys pressed while QuickNote itself is frontmost, including in the capture panel, where the
    /// same chord saves and closes it.
    func startLocal() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            detector.keyPressed()
        case .flagsChanged:
            if detector.modifiersChanged(to: ModifierKeys(event.modifierFlags), at: event.timestamp) {
                onTrigger()
            }
        default:
            break
        }
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
