import Foundation
import SwiftData
import Testing
@testable import QuickNote

/// The panel is the only place that writes and deletes notes on its own, so its rules are checked
/// against a real (in-memory) store.
@MainActor
struct CapturePanelControllerTests {
    private let container: ModelContainer
    private let capture: CapturePanelController

    init() throws {
        // A name of its own, so tests never share a store.
        let configuration = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Note.self, configurations: configuration)
        capture = CapturePanelController(container: container)
    }

    /// Adds notes, oldest first.
    private func add(_ texts: String...) throws {
        for (index, text) in texts.enumerated() {
            container.mainContext.insert(Note(text: text, createdAt: Date(timeIntervalSince1970: Double(index))))
        }
        try container.mainContext.save()
    }

    /// Every stored note's text, oldest first.
    private func storedTexts() throws -> [String] {
        let oldestFirst = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.createdAt)])
        return try container.mainContext.fetch(oldestFirst).map(\.text)
    }

    @Test func savesTheNewNoteTrimmed() throws {
        capture.show()
        capture.draft.text = "  An idea \n"
        capture.commit()
        #expect(try storedTexts() == ["An idea"])
    }

    @Test func blankNewNoteIsNotSaved() throws {
        capture.show()
        capture.draft.text = " \n "
        capture.commit()
        #expect(try storedTexts().isEmpty)
    }

    @Test func committingTwiceSavesOnce() throws {
        capture.show()
        capture.draft.text = "Once"
        capture.commit()
        capture.commit()
        #expect(try storedTexts() == ["Once"])
    }

    @Test func flipsNewestFirstAndWrapsAroundKeepingTheDraft() throws {
        try add("one", "two", "three")
        capture.show()
        capture.draft.text = "draft"
        capture.flip(by: 1)
        #expect(capture.draft.text == "three")
        #expect(capture.draft.caption.hasPrefix("Note 3 of 3"))
        capture.flip(by: 1)
        #expect(capture.draft.text == "two")
        capture.flip(by: 1)
        #expect(capture.draft.text == "one")
        capture.flip(by: 1)
        #expect(capture.draft.text == "draft")
        #expect(capture.draft.caption == "New note")
        capture.commit()
        #expect(try storedTexts() == ["one", "two", "three", "draft"])
    }

    @Test func flipsTheOtherWayFromTheNewNoteToTheOldest() throws {
        try add("one", "two", "three")
        capture.show()
        capture.draft.text = "draft"
        capture.flip(by: -1)
        #expect(capture.draft.text == "one")
        capture.flip(by: -1)
        #expect(capture.draft.text == "two")
        capture.flip(by: 1)
        #expect(capture.draft.text == "one")
        capture.flip(by: 1)
        #expect(capture.draft.text == "draft")
    }

    @Test func savesEditsAndDeletesOnlyTheNoteClearedHere() throws {
        // The blank one stands for a note just made with ⌘N in the main window.
        try add("keep", "", "edit me", "clear me")
        capture.show()
        capture.flip(by: 1)  // "clear me"
        capture.draft.text = ""
        capture.flip(by: 1)  // "edit me"
        capture.draft.text = "edited"
        capture.commit()
        #expect(try storedTexts() == ["keep", "", "edited"])
    }
}
