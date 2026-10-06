import AppKit
import ApplicationServices
import Observation

/// Tracks whether QuickNote is trusted for Accessibility, which macOS
/// requires before an app can observe key presses in other apps.
@MainActor
@Observable
final class AccessibilityPermission {
    private(set) var isGranted = AXIsProcessTrusted()

    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Runs `action` as soon as the permission is granted, showing the system
    /// prompt first if it hasn't been granted yet.
    func whenGranted(_ action: @escaping @MainActor () -> Void) {
        if isGranted {
            action()
            return
        }
        requestPrompt()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if AXIsProcessTrusted() {
                    self.isGranted = true
                    action()
                    return
                }
            }
        }
    }

    /// Opens the Accessibility list. Asks for the permission first so this exact copy of the app is
    /// listed there: other builds (e.g. QuickNote Dev) have their own entries.
    func openSystemSettings() {
        requestPrompt()
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func requestPrompt() {
        // Literal value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
