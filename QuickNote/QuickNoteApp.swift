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
            MenuBarContent(capture: appDelegate.capture, voice: appDelegate.voice) { appDelegate.showSettings() }
        } label: {
            MenuBarIcon(voice: appDelegate.voice)
        }
    }
}

/// The lightbulb, or a microphone while a voice note is being recorded.
private struct MenuBarIcon: View {
    let voice: VoiceCaptureController

    var body: some View {
        Label("QuickNote", systemImage: voice.isRecording ? "mic.fill" : "lightbulb")
    }
}

private struct MenuBarContent: View {
    let capture: CapturePanelController
    let voice: VoiceCaptureController
    let showSettings: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var menuTitle: String {
        if voice.isTranscribing { return "Transcribing…" }
        return voice.isRecording ? "Stop Recording  ⌃⌥R" : "Record Voice Note  ⌃⌥R"
    }

    var body: some View {
        Button("New Quick Note") { capture.show() }
        Button(menuTitle) { voice.toggle() }
            .disabled(voice.isTranscribing)
        Button("Open QuickNote") {
            openWindow(id: "main")
            NSApp.activate()
        }
        if voice.unsentCount > 0 {
            Button("Unsent Recordings (\(voice.unsentCount))…") { voice.showUnsentRecordings() }
        }
        Button("Settings…", action: showSettings)
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
