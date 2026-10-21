import Foundation
import SwiftData

@Model
final class Note {
    var text: String
    var createdAt: Date
    var updatedAt: Date
    /// Attached files, as names relative to `Attachments.folder` (`<UUID>/<file name>`).
    var attachments: [String] = []

    init(text: String = "", attachments: [String] = [], createdAt: Date = .now) {
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// First non-empty line, used as the note's title in lists; an attachment-only note uses its first file's name.
    var title: String {
        lines.first ?? attachments.first.map { ($0 as NSString).lastPathComponent } ?? "New Note"
    }

    /// Second non-empty line, shown under the title in the sidebar.
    var preview: String {
        lines.dropFirst().first ?? ""
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }

    /// Non-empty lines with their Markdown marks removed.
    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { MarkdownParser.plainText(String($0)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
