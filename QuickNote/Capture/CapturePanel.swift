import AppKit

/// Spotlight-style floating panel. It's non-activating, so the app you were
/// typing in stays frontmost underneath and gets focus back on close.
final class CapturePanel: NSPanel {
    var onSubmit: (() -> Void)?
    var onRightShiftTap: (() -> Void)?

    private var rightShiftTap = ModifierTapDetector()

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
        title = "QuickNote"  // hidden, but VoiceOver names the window by it
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

    // Intercept Esc and ⌘↩ here: the text view would otherwise swallow Esc
    // (it triggers autocomplete) and insert a newline for ⌘↩.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            rightShiftTap.keyPressed()
            // Only the four real modifiers: Caps Lock and the keypad/fn flags don't count.
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // While a Japanese, Chinese or Korean word is being composed, Esc cancels it: leave that to the text view.
            let isComposing = (firstResponder as? NSTextInputClient)?.hasMarkedText() == true
            let isEscape = event.keyCode == 53 && !isComposing
            let isCommandReturn = (event.keyCode == 36 || event.keyCode == 76) && modifiers == .command
            if isEscape || isCommandReturn {
                onSubmit?()
                return
            }
        case .flagsChanged:
            // Device-dependent bit for the right Shift key (NX_DEVICERSHIFTKEYMASK),
            // so left Shift is never mistaken for it.
            let rightShiftDown = event.modifierFlags.rawValue & 0x4 != 0
            if rightShiftTap.modifierChanged(keyCode: event.keyCode, isDown: rightShiftDown, timestamp: event.timestamp) {
                onRightShiftTap?()
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}
