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
            .overlay(FileDragSource(url: url, onClick: open))
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

/// Lets a chip be dragged out to Finder, a chat, a terminal… as the file itself, and opens it on a plain
/// click. AppKit because SwiftUI's `.onDrag` on a button never starts a drag (the button keeps the mouse),
/// and a plain file URL is what browsers, Electron apps and terminals accept.
private struct FileDragSource: NSViewRepresentable {
    let url: URL
    let onClick: () -> Void

    func makeNSView(context: Context) -> SourceView { SourceView() }

    func updateNSView(_ view: SourceView, context: Context) {
        view.url = url
        view.onClick = onClick
    }

    final class SourceView: NSView, NSDraggingSource {
        var url: URL?
        var onClick: (() -> Void)?
        private var mouseDown: NSEvent?

        // Left clicks only: right clicks and hovering still reach the chip's menu and remove button.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .leftMouseDown ? super.hitTest(point) : nil
        }

        // Otherwise dragging a chip in the capture panel moves the panel.
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            mouseDown = event
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDown, let url,
                  hypot(event.locationInWindow.x - down.locationInWindow.x,
                        event.locationInWindow.y - down.locationInWindow.y) > 3
            else { return }
            mouseDown = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let point = convert(down.locationInWindow, from: nil)
            item.setDraggingFrame(
                NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32),
                contents: NSWorkspace.shared.icon(forFile: url.path)
            )
            beginDraggingSession(with: [item], event: down, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            if mouseDown != nil {
                onClick?()
            }
            mouseDown = nil
        }

        // Only out to other apps: dropped on a note here it would just attach a second copy.
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}
