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
            fatalError("Could not open the notes database: \(error)")
        }
        super.init()
    }

    /// `~/Library/Application Support/<bundle id>/Notes.store`. Outside the sandbox SwiftData's default
    /// is a `default.store` shared by every app, and the Debug build has its own bundle id so it gets
    /// its own notes.
    private static func storeURL() throws -> URL {
        let folder = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Notes.store")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        monitor.startLocal()
        permission.whenGranted { [weak self] in
            self?.monitor.startGlobal()
        }
    }

    // Keep running with no windows open so the shortcut keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
