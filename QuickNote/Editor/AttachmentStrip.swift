import QuickLookThumbnailing
import SwiftUI

/// A note's attached files, as a row of chips under the editor. Clicking one opens it.
struct AttachmentStrip: View {
    let names: [String]
    let onRemove: (String) -> Void

    var body: some View {
        if !names.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(names, id: \.self) { name in
                        AttachmentChip(name: name) { onRemove(name) }
                    }
                }
                // Room for the remove button that sticks out of a chip's corner.
                .padding(.top, 5)
                .padding(.trailing, 5)
            }
        }
    }
}

/// The button that opens the file picker, shown at the end of the command list.
struct AttachButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Attach", systemImage: "paperclip")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help("Attach files. You can also drop or paste them into the note.")
    }
}

private struct AttachmentChip: View {
    let name: String
    let onRemove: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

    private var url: URL { Attachments.url(for: name) }
    private var displayName: String { Attachments.displayName(name) }
    private var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 5) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        Image(systemName: exists ? "doc" : "exclamationmark.triangle")
                    }
                }
                .frame(width: 22, height: 22)
                Text(displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .font(.caption)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background(.quaternary, in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .accessibilityLabel("Remove \(displayName)")
            }
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open", action: open)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Button("Remove", role: .destructive, action: onRemove)
        }
        .help(exists ? "Open \(displayName)" : "\(displayName) is missing")
        .accessibilityLabel(exists ? "Attachment \(displayName)" : "Missing attachment \(displayName)")
        .accessibilityHint("Opens the file")
        .task(id: name) {
            // Quick Look would draw a generic icon for a missing file, hiding the warning.
            guard exists else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: 22, height: 22), scale: 2, representationTypes: .all
            )
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }

    private func open() {
        NSWorkspace.shared.open(url)
    }
}
