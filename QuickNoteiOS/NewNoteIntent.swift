import AppIntents
import Observation

/// iPhone's stand-in for the ⌃⌥ hotkey: the Action Button, Back Tap, Siri and Shortcuts can all run this.
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Quick Note"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NewNoteRequests.shared.count += 1
        return .result()
    }
}

/// Listed under the app so the Action Button and Back Tap can pick it without building a Shortcut first.
struct QuickNoteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewNoteIntent(),
            phrases: ["New quick note in \(.applicationName)"],
            shortTitle: "New Quick Note",
            systemImageName: "square.and.pencil"
        )
    }
}

/// Bumped by every `NewNoteIntent`; the capture screen watches it and starts a fresh note.
@MainActor
@Observable
final class NewNoteRequests {
    static let shared = NewNoteRequests()
    var count = 0
}
