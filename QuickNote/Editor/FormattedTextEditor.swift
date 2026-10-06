import SwiftUI

/// A text editor for notes: Markdown shown styled as you type, plus a small toolbar over any
/// selected text that writes the same Markdown.
struct FormattedTextEditor: View {
    @Binding var text: String
    var fontSize: CGFloat
    /// Changing this moves keyboard focus into the editor. `nil` leaves focus alone.
    var focusToken: Int? = nil

    @State private var controller = MarkdownEditorController()

    var body: some View {
        MarkdownEditorRepresentable(text: $text, fontSize: fontSize, focusToken: focusToken, controller: controller)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    if let selection = controller.selection {
                        // Above the selection when there's room, otherwise below it.
                        let estimatedWidth: CGFloat = 280
                        SelectionToolbar(selection: selection, controller: controller)
                            .fixedSize()
                            .offset(
                                x: min(max(0, selection.x - 8), max(0, geometry.size.width - estimatedWidth)),
                                y: selection.top >= 42 ? selection.top - 40 : selection.bottom + 6
                            )
                    }
                }
            }
    }
}

/// Where the selection is (top-left origin, in the editor's coordinates) and how it's styled.
struct SelectionInfo: Equatable {
    var top: CGFloat
    var bottom: CGFloat
    var x: CGFloat
    var active: Set<InlineStyle>
    var lineKind: LineKind
}

@MainActor
@Observable
final class MarkdownEditorController {
    var selection: SelectionInfo?
    @ObservationIgnored weak var textView: MarkdownTextView?

    func toggle(_ style: InlineStyle) { textView?.toggle(style) }
    func toggleLineKind(_ kind: LineKind) { textView?.toggleLineKind(kind) }
}

private struct SelectionToolbar: View {
    let selection: SelectionInfo
    let controller: MarkdownEditorController

    var body: some View {
        HStack(spacing: 2) {
            styleButton("bold", .bold, "Bold (⌘B)")
            styleButton("italic", .italic, "Italic (⌘I)")
            styleButton("strikethrough", .strike, "Strikethrough (⇧⌘X)")
            styleButton("highlighter", .highlight, "Highlight (⇧⌘H)")
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(width: 1, height: 16)
                .padding(.horizontal, 3)
            lineButton("textformat.size", .title, "Title (# at the start of a line)")
            lineButton("list.bullet", .bullet, "List (- at the start of a line)")
            lineButton("checklist", .todo(done: false), "To-do ([ ] at the start of a line)")
        }
        .padding(4)
        .background(Color(red: 0.13, green: 0.14, blue: 0.17), in: .rect(cornerRadius: 10))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }

    private func styleButton(_ symbol: String, _ style: InlineStyle, _ help: String) -> some View {
        toolbarButton(symbol, isOn: selection.active.contains(style), help: help) {
            controller.toggle(style)
        }
    }

    private func lineButton(_ symbol: String, _ kind: LineKind, _ help: String) -> some View {
        toolbarButton(symbol, isOn: selection.lineKind.isSameKind(as: kind), help: help) {
            controller.toggleLineKind(kind)
        }
    }

    private func toolbarButton(_ symbol: String, isOn: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(isOn ? Color.white.opacity(0.2) : .clear, in: .rect(cornerRadius: 7))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct MarkdownEditorRepresentable: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    let focusToken: Int?
    let controller: MarkdownEditorController

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let (scrollView, textView) = MarkdownTextView.makeScrollable(fontSize: fontSize)
        textView.delegate = context.coordinator
        textView.string = text
        textView.restyle()
        context.coordinator.textView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if textView.string != text {
            // Changed from outside, e.g. flipping to an older note in the capture panel.
            textView.string = text
            textView.restyle()
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if let focusToken, focusToken != coordinator.focusToken {
            coordinator.focusToken = focusToken
            Task { @MainActor in
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorRepresentable
        weak var textView: MarkdownTextView?
        var focusToken: Int?

        init(parent: MarkdownEditorRepresentable) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            publishSelection()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            textView?.restyleIfLineChanged()
            publishSelection()
        }

        /// Tells the toolbar where the selection is, or hides it when nothing is selected.
        func publishSelection() {
            var info: SelectionInfo?
            if let textView, let scrollView = textView.enclosingScrollView,
               let layout = textView.layoutManager, let container = textView.textContainer,
               textView.window?.firstResponder === textView {
                let selection = textView.selectedRange()
                if selection.length > 0 {
                    let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
                    var firstLine = NSRange()
                    layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &firstLine)
                    let origin = textView.textContainerOrigin
                    let first = layout.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, firstLine), in: container)
                        .offsetBy(dx: origin.x, dy: origin.y)
                    let whole = layout.boundingRect(forGlyphRange: glyphs, in: container)
                        .offsetBy(dx: origin.x, dy: origin.y)
                    // SwiftUI measures from the top edge; the scroll view may count from either.
                    let height = scrollView.bounds.height
                    let firstInScroll = textView.convert(first, to: scrollView)
                    let wholeInScroll = textView.convert(whole, to: scrollView)
                    let flipped = scrollView.isFlipped
                    info = SelectionInfo(
                        top: flipped ? firstInScroll.minY : height - firstInScroll.maxY,
                        bottom: flipped ? wholeInScroll.maxY : height - wholeInScroll.minY,
                        x: firstInScroll.minX,
                        active: Set(InlineStyle.allCases.filter { textView.isActive($0) }),
                        lineKind: textView.currentLineKind
                    )
                }
            }
            if parent.controller.selection != info {
                parent.controller.selection = info
            }
        }
    }
}
