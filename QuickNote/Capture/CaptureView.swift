import SwiftUI

@MainActor
@Observable
final class CaptureDraft {
    var text = ""
    /// Which note is showing, e.g. "New note" or "Note 3 of 3 · 2 hours ago".
    var caption = "New note"
    /// Whether there are older notes to flip back to.
    var canBrowse = false
    /// Bumped every time the panel opens so the view can refocus the editor.
    private(set) var session = 0

    func begin() {
        text = ""
        session += 1
    }
}

struct CaptureView: View {
    @Bindable var draft: CaptureDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FormattedTextEditor(text: $draft.text, fontSize: 16, focusToken: draft.session)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("What's the idea?")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                }

            MarkdownCheatSheet()

            HStack {
                Text(draft.caption)
                    .monospacedDigit()
                Spacer()
                Text(draft.canBrowse ? "select text for more · . and - for older · esc saves" : "select text for more · esc saves")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 30)
        .padding([.horizontal, .bottom], 16)
        .frame(minWidth: 500, minHeight: 260)
        .background(.regularMaterial)
    }
}
