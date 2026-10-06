import ServiceManagement
import SwiftUI

@main
struct QuickNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("QuickNote", id: "main") {
            NotesListView()
                .environment(appDelegate.permission)
        }
        .modelContainer(appDelegate.container)
        .commands {
            // ⌘N creates a note (see NotesListView) instead of a new window.
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra("QuickNote", systemImage: "lightbulb") {
            MenuBarContent(capture: appDelegate.capture)
        }
    }
}

private struct MenuBarContent: View {
    let capture: CapturePanelController
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("New Quick Note") { capture.show() }
        Button("Open QuickNote") {
            openWindow(id: "main")
            NSApp.activate()
        }
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
