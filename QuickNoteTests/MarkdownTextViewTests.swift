import AppKit
import SwiftUI
import Testing
@testable import QuickNote

@MainActor
struct MarkdownTextViewTests {
    private let sample = """
        # Bike rack that folds flat
        Hangs against the hallway wall, **flush when folded**.
        - Hinge at the base, a magnet at the top
        - Fits a road bike? ==Measure the hallway first==
        [ ] Ask the hardware store about hinges
        [x] Look up wall anchors
        """

    /// A text view in an offscreen window, so it can take focus like in the app.
    private func makeEditor(text: String) -> (NSWindow, MarkdownTextView) {
        let (scrollView, textView) = MarkdownTextView.makeScrollable(fontSize: 16)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 280), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scrollView
        textView.string = text
        textView.restyle()
        return (window, textView)
    }

    private func font(of textView: MarkdownTextView, at index: Int) -> NSFont? {
        textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    @Test func marksCollapseAwayFromTheCaret() {
        let (_, textView) = makeEditor(text: sample)
        let bold = (textView.string as NSString).range(of: "**flush")
        #expect(font(of: textView, at: bold.location)!.pointSize < 1)
        #expect(font(of: textView, at: 0)!.pointSize < 1)  // the "#" of the title
    }

    @Test func marksStayHiddenWhileEditing() {
        let (window, textView) = makeEditor(text: sample)
        window.makeFirstResponder(textView)
        let bold = (textView.string as NSString).range(of: "**flush")
        textView.setSelectedRange(NSRange(location: bold.location + 3, length: 0))
        #expect(font(of: textView, at: bold.location)!.pointSize < 1)
    }

    @Test func caretStepsOverHiddenMarks() {
        let (window, textView) = makeEditor(text: "a **b** c")
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.setSelectedRange(NSRange(location: 3, length: 0))  // into the opening ** going right
        #expect(textView.selectedRange().location == 4)
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        textView.setSelectedRange(NSRange(location: 6, length: 0))  // into the closing ** going left
        #expect(textView.selectedRange().location == 5)
    }

    @Test func backspaceAfterALineMarkRemovesIt() {
        let (window, textView) = makeEditor(text: "- item\n[ ] task")
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.deleteBackward(nil)
        #expect(textView.string == "item\n[ ] task")
    }

    @Test func typingAtTheEndOfStyledTextStaysInside() {
        let (window, textView) = makeEditor(text: "**ab**")
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertText("c", replacementRange: textView.selectedRange())
        textView.insertText("d", replacementRange: textView.selectedRange())
        #expect(textView.string == "**abcd**")
    }

    @Test func styledTextGetsItsLook() {
        let (_, textView) = makeEditor(text: sample)
        let flush = (textView.string as NSString).range(of: "flush when folded")
        #expect(font(of: textView, at: flush.location)!.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(font(of: textView, at: 2)!.pointSize > 16)  // title
    }

    @Test func toolbarCommandsWriteMarkdown() {
        let (window, textView) = makeEditor(text: "an idea worth keeping")
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 4))
        textView.toggle(.bold)
        #expect(textView.string == "an **idea** worth keeping")
        textView.toggle(.bold)
        #expect(textView.string == "an idea worth keeping")
        textView.toggleLineKind(.todo(done: false))
        #expect(textView.string == "[ ] an idea worth keeping")
        textView.toggleLineKind(.bullet)
        #expect(textView.string == "- an idea worth keeping")
    }

    /// Renders the capture panel with a selection to a PNG when QUICKNOTE_SNAPSHOT_DIR is set
    /// (pass TEST_RUNNER_QUICKNOTE_SNAPSHOT_DIR to xcodebuild), for checking the look by eye.
    @Test func snapshotCapturePanel() async throws {
        guard let directory = ProcessInfo.processInfo.environment["QUICKNOTE_SNAPSHOT_DIR"] else { return }
        let draft = CaptureDraft()
        draft.begin()
        draft.text = sample
        draft.attachments = ["ABC/Pasted Image 2026-10-16 09.05.07.png", "DEF/spec.pdf"]
        let host = NSHostingView(rootView: CaptureView(draft: draft, onPickFiles: {}).frame(width: 620, height: 320))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))

        let textView = try #require(findTextView(in: host))
        window.makeFirstResponder(textView)
        let flush = (textView.string as NSString).range(of: "flush when folded")
        textView.setSelectedRange(flush)
        try await Task.sleep(for: .milliseconds(300))

        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appending(path: "capture-panel.png"))
    }

    private func findTextView(in view: NSView) -> MarkdownTextView? {
        if let textView = view as? MarkdownTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }
}
