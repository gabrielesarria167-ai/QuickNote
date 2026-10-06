import Foundation
import SwiftData

@Model
final class Note {
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(text: String = "", createdAt: Date = .now) {
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// First non-empty line, used as the note's title in lists.
    var title: String {
        lines.first ?? "New Note"
    }

    /// Second non-empty line, shown under the title in the sidebar.
    var preview: String {
        lines.dropFirst().first ?? ""
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
