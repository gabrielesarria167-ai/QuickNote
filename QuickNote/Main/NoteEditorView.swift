import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(OpenNoteTracker.self) private var openNote

    var body: some View {
        FormattedTextEditor(text: $note.text, fontSize: 14, onAttach: attach)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    AttachmentStrip(names: note.attachments) { name in
                        note.attachments.removeAll { $0 == name }
                    }
                    HStack {
                        MarkdownCheatSheet()
                        Spacer()
                        AttachButton {
                            Attachments.pickFiles(sheetFor: openNote.window) { keep(Attachments.add($0)) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .navigationTitle(note.title)
            .navigationSubtitle(note.createdAt.formatted(date: .abbreviated, time: .shortened))
            .onChange(of: note.text) {
                note.updatedAt = .now
            }
            .onChange(of: note.attachments) {
                note.updatedAt = .now
            }
            .background(WindowReader { openNote.window = $0 })
            .onAppear { openNote.note = note }
            // The next note's editor may already have appeared, so only clear our own entry.
            .onDisappear {
                if openNote.note === note { openNote.note = nil }
            }
    }

    private func attach(_ pasteboard: NSPasteboard) -> Bool {
        let added = Attachments.add(from: pasteboard)
        keep(added)
        return !added.isEmpty
    }

    /// Saves right away: a reference lost in a crash would let the launch sweep delete the copied file.
    private func keep(_ added: [String]) {
        guard !added.isEmpty else { return }
        note.attachments += added
        try? note.modelContext?.save()
    }
}
