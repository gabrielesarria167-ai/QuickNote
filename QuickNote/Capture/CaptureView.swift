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
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $draft.text)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("What's the idea?")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Text(draft.caption)
                    .monospacedDigit()
                Spacer()
                Text(draft.canBrowse ? "right ⇧ older · esc or ⌘↩ save" : "esc or ⌘↩ save")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 30)
        .padding([.horizontal, .bottom], 16)
        .frame(minWidth: 420, minHeight: 180)
        .background(.regularMaterial)
        .onAppear { isFocused = true }
        .onChange(of: draft.session) { isFocused = true }
    }
}
