import ServiceManagement
import SwiftUI

@main
struct QuickNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("QuickNote", id: "main") {
            NotesListView()
                .environment(appDelegate.permission)
                .environment(appDelegate.voice)
                .environment(appDelegate.openNote)
        }
        .modelContainer(appDelegate.container)
        .commands {
            // ⌘N creates a note (see NotesListView) instead of a new window.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showSettings() }
                    .keyboardShortcut(",")
            }
        }

        MenuBarExtra {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            MenuBarIcon(appDelegate: appDelegate)
        }
    }
}

/// The lightbulb, or a microphone while a voice note is being recorded.
private struct MenuBarIcon: View {
    let appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label("QuickNote", systemImage: appDelegate.voice.isRecording ? "mic.fill" : "lightbulb")
            .onAppear { appDelegate.openMainWindow = { openWindow(id: "main") } }
    }
}

private struct MenuBarContent: View {
    let appDelegate: AppDelegate
    private var capture: CapturePanelController { appDelegate.capture }
    private var voice: VoiceCaptureController { appDelegate.voice }
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var menuTitle: String {
        if voice.isTranscribing { return "Transcribing…" }
        return voice.isRecording ? "Stop Recording  ⌃⌥R" : "Record Voice Note  ⌃⌥R"
    }

    var body: some View {
        Button("New Quick Note") { capture.show() }
        Button(menuTitle) { voice.toggle() }
            .disabled(voice.isTranscribing)
        Button("Open QuickNote") { appDelegate.showMainWindow() }
        if voice.unsentCount > 0 {
            Menu("Unsent Recordings") {
                ForEach(voice.unsent, id: \.url) { recording in
                    Button(UnsentRecordings.menuLabel(date: recording.date, duration: recording.duration)) {
                        voice.resume(recording)
                    }
                }
                Divider()
                Button("Transcribe All") { voice.resumeAll() }
                Button("Show in Finder") { voice.showUnsentRecordings() }
            }
            .disabled(voice.isRecording)
        }
        if !voice.recentlyTranscribed.isEmpty {
            Menu("Recently Transcribed") {
                ForEach(voice.recentlyTranscribed, id: \.url) { recording in
                    Button(UnsentRecordings.menuLabel(date: recording.date, duration: recording.duration)) {
                        voice.transcribeAgain(recording)
                    }
                }
                Divider()
                Text("Click one to transcribe it again. Kept for 7 days.")
                Button("Show in Finder") { voice.showRecentlyTranscribed() }
            }
            .disabled(voice.isRecording)
        }
        Button("Settings…") { appDelegate.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        Divider()
        Button("Quit QuickNote") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
