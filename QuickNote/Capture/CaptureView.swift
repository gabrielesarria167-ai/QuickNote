import SwiftUI

@MainActor
@Observable
final class CaptureDraft {
    var text = ""
    /// Files attached to the note showing, as stored names (see `Attachments`).
    var attachments: [String] = []
    /// Which note is showing, e.g. "New note" or "Note 3 of 3 · 2 hours ago".
    var caption = "New note"
    /// Whether there are older notes to flip back to.
    var canBrowse = false
    /// Bumped every time the panel opens so the view can refocus the editor.
    private(set) var session = 0

    func begin() {
        text = ""
        attachments = []
        session += 1
    }
}

struct CaptureView: View {
    @Bindable var draft: CaptureDraft
    let onPickFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormattedTextEditor(text: $draft.text, fontSize: 16, focusToken: draft.session, onAttach: attach)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty && draft.attachments.isEmpty {
                        Text("What's the idea?")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }

            AttachmentStrip(names: draft.attachments) { name in
                draft.attachments.removeAll { $0 == name }
            }

            HStack {
                MarkdownCheatSheet()
                Spacer()
                AttachButton(action: onPickFiles)
            }

            HStack {
                Text(draft.caption)
                    .monospacedDigit()
                Spacer()
                Text(draft.canBrowse ? "select text for more · . - older · < z newer · esc saves" : "select text for more · esc saves")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 30)
        .padding([.horizontal, .bottom], 16)
        .frame(minWidth: 500, minHeight: 260)
        .background(.regularMaterial)
    }

    private func attach(_ pasteboard: NSPasteboard) -> Bool {
        let added = Attachments.add(from: pasteboard)
        draft.attachments += added
        return !added.isEmpty
    }
}
