import AppKit

/// Files attached to notes, copied into `Application Support/<bundle id>/Attachments/<UUID>/<file name>`.
/// A note stores the `<UUID>/<file name>` part, so two files with the same name never clash and the
/// original name is what the user sees.
enum Attachments {
    static var folder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote", directoryHint: .isDirectory)
            .appending(path: "Attachments", directoryHint: .isDirectory)
    }

    static func url(for name: String, in folder: URL = Attachments.folder) -> URL {
        folder.appending(path: name)
    }

    /// The file name shown for a stored attachment.
    static func displayName(_ name: String) -> String {
        (name as NSString).lastPathComponent
    }

    /// Copies files (or folders) in and returns their stored names. A file that can't be copied is left out.
    // shortcut: copies on the main thread, so a multi-GB file stalls the UI; move off the main actor if that bites.
    static func add(_ files: [URL], in folder: URL = Attachments.folder) -> [String] {
        files.compactMap { file in
            store(in: folder, named: file.lastPathComponent) { try FileManager.default.copyItem(at: file, to: $0) }
        }
    }

    /// Attaches what's on a pasteboard (paste or drop): files, or else an image such as a screenshot.
    /// An image that comes with text is left alone, so copied text with a picture still pastes as text.
    /// Returns `[]` when there's nothing to attach.
    static func add(from pasteboard: NSPasteboard, in folder: URL = Attachments.folder, now: Date = .now) -> [String] {
        let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if !files.isEmpty {
            return add(files, in: folder)
        }
        guard pasteboard.string(forType: .string) == nil,
              let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        else { return [] }
        let name = "Pasted Image " + UnsentRecordings.fileName(for: now, fileExtension: "png")
        return [store(in: folder, named: name) { try png.write(to: $0) }].compactMap { $0 }
    }

    /// Lets the user choose files to attach: as a sheet on `window` if given, otherwise app-modal,
    /// so no other window can change the note while the picker is up.
    @MainActor
    static func pickFiles(sheetFor window: NSWindow?, completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Attach"
        if let window {
            panel.beginSheetModal(for: window) { completion($0 == .OK ? panel.urls : []) }
        } else {
            completion(panel.runModal() == .OK ? panel.urls : [])
        }
    }

    /// Deletes stored files no note refers to: from deleted notes, removed attachments or drafts
    /// that were never saved.
    static func removeOrphans(keeping names: some Sequence<String>, in folder: URL = Attachments.folder) {
        let kept = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
        let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where !kept.contains(entry.lastPathComponent) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// Writes one file into a new `<UUID>` folder and returns its stored name, or nil (and no folder) on failure.
    private static func store(in folder: URL, named fileName: String, write: (URL) throws -> Void) -> String? {
        let id = UUID().uuidString
        let directory = folder.appending(path: id, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try write(directory.appending(path: fileName))
            return "\(id)/\(fileName)"
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }
}
