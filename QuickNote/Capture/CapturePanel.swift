import AppKit

/// Spotlight-style floating panel. It's non-activating, so the app you were
/// typing in stays frontmost underneath and gets focus back on close.
final class CapturePanel: NSPanel {
    var onSubmit: (() -> Void)?
    /// `.` and `-` pressed together: flip back to an older note.
    var onFlip: (() -> Void)?

    private var flipChord = KeyChordDetector()
    /// A `.` or `-` press kept back while waiting to see if the other key joins it.
    private var heldEvent: NSEvent?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Keys are handled here, before the text view sees them: Esc and ⌘↩ save (the text view would
    // otherwise swallow Esc for autocomplete and insert a newline for ⌘↩), and the `.` `-` chord
    // flips notes without typing either character.
    override func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.type {
        case .keyDown:
            let decision = flipChord.keyDown(
                event.characters,
                at: event.timestamp,
                isRepeat: event.isARepeat,
                hasShortcutModifier: !modifiers.isDisjoint(with: [.command, .control, .option])
            )
            switch decision {
            case .chord:
                heldEvent = nil
                onFlip?()
                return
            case .swallow:
                return
            case .hold:
                hold(event)
                return
            case .flushThenHold:
                deliverHeld()
                hold(event)
                return
            case .flushThenPass:
                deliverHeld()
            case .pass:
                break
            }
            let isEscape = event.keyCode == 53
            let isCommandReturn = (event.keyCode == 36 || event.keyCode == 76) && modifiers == .command
            if isEscape || isCommandReturn {
                onSubmit?()
                return
            }
        case .keyUp:
            switch flipChord.keyUp(event.characters) {
            case .swallow:
                return
            case .flushThenPass:
                deliverHeld()
            default:
                break
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func hold(_ event: NSEvent) {
        heldEvent = event
        let generation = flipChord.generation
        let delay = flipChord.window
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.flipChord.timedOut(generation: generation) else { return }
            self.deliverHeld()
        }
    }

    /// Types the held `.` or `-` after all.
    private func deliverHeld() {
        guard let event = heldEvent else { return }
        heldEvent = nil
        if isVisible {
            super.sendEvent(event)
        }
    }
}
