import AppKit
import SwiftData

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let permission = AccessibilityPermission()
    private(set) lazy var capture = CapturePanelController(container: container)
    private lazy var monitor = HotkeyMonitor { [weak self] in
        self?.capture.toggle()
    }

    private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    override init() {
        do {
            let configuration = Self.isRunningTests
                ? ModelConfiguration(isStoredInMemoryOnly: true)
                : ModelConfiguration(url: try Self.storeURL())
            container = try ModelContainer(for: Note.self, configurations: configuration)
        } catch {
            Self.quit(becauseNotesCantOpen: error)
        }
        super.init()
    }

    /// `~/Library/Application Support/<bundle id>/Notes.store`. Outside the sandbox SwiftData's default
    /// is a `default.store` shared by every app, and the Debug build has its own bundle id so it gets
    /// its own notes.
    private static let storeFolder = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote", directoryHint: .isDirectory)

    private static func storeURL() throws -> URL {
        try FileManager.default.createDirectory(at: storeFolder, withIntermediateDirectories: true)
        return storeFolder.appending(path: "Notes.store")
    }

    /// The app can't work without its notes (a damaged store, a full disk): say so and where they are,
    /// instead of crashing before any window shows up.
    private static func quit(becauseNotesCantOpen error: Error) -> Never {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "QuickNote can't open your notes"
        alert.informativeText = "\(error.localizedDescription)\n\nThey're in \(storeFolder.path). Nothing was changed."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Show in Finder")
        NSApplication.shared.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([storeFolder])
        }
        exit(1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        monitor.startLocal()
        permission.whenGranted { [weak self] in
            self?.monitor.startGlobal()
        }
    }

    // Quitting (log out, restart, an update) with the panel open would otherwise drop what's typed in it.
    func applicationWillTerminate(_ notification: Notification) {
        capture.commit()
    }

    // Keep running with no windows open so the shortcut keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
