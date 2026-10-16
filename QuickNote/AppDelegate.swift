import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container: ModelContainer
    let permission = AccessibilityPermission()
    private(set) lazy var capture = CapturePanelController(container: container)
    let openNote = OpenNoteTracker()
    /// Doesn't touch the Keychain until the Settings window or a recording asks.
    let voiceSettings = VoiceSettings(keyStore: KeychainKeyStore())
    private(set) lazy var voice = VoiceCaptureController(
        container: container,
        capture: capture,
        openNote: openNote,
        settings: voiceSettings,
        openSettings: { [weak self] in self?.showSettings() }
    )
    /// The Settings window. Owned here, not a SwiftUI `Settings` scene, so the menu bar item, the ⌘,
    /// command and the recording pill (which has no SwiftUI environment) can all open the same one.
    private lazy var settingsWindow: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: voiceSettings)))
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        // Remembers where the user put it; centred only when there is nothing remembered.
        needsCentering = !window.setFrameUsingName("Settings")
        window.setFrameAutosaveName("Settings")
        return window
    }()
    private var needsCentering = true
    private lazy var monitor = HotkeyMonitor(
        onTrigger: { [weak self] in self?.capture.toggle() },
        onRecord: { [weak self] in self?.voice.toggle() }
    )

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
        VoiceRecorder.cleanUpLeftoverRecordings()
        // Only when the notes could be read, so a failed fetch can't look like "no attachments in use".
        if let notes = try? container.mainContext.fetch(FetchDescriptor<Note>()) {
            Attachments.removeOrphans(keeping: notes.flatMap(\.attachments))
        }
        voice.refreshUnsentCount()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // The user may have emptied the folder in Finder.
            MainActor.assumeIsolated { self?.voice.refreshUnsentCount() }
        }
        monitor.startLocal()
        permission.whenGranted { [weak self] in
            self?.monitor.startGlobal()
        }
    }

    /// Brings up the Settings window.
    func showSettings() {
        NSApp.activate()
        voiceSettings.refreshKeyState()
        let window = settingsWindow
        if needsCentering {
            needsCentering = false
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    /// A recording that is still going, or waiting for Gemini, is saved first: Apple's text goes to
    /// its note and the audio is kept in Unsent Recordings.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !Self.isRunningTests, voice.isRecording {
            voice.saveForQuit()
        }
        return .terminateNow
    }

    // Keep running with no windows open so the shortcut keeps working.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
