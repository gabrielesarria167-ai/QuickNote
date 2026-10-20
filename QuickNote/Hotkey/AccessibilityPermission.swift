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
    /// prompt first if it hasn't been granted yet, and again each time it's turned back on.
    func whenGranted(_ action: @escaping @MainActor () -> Void) {
        if isGranted {
            action()
        } else {
            requestPrompt()
        }
        pollTask?.cancel()
        // Keeps checking once granted: the permission can be turned off (and on again) while the app runs.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                guard trusted != self.isGranted else { continue }
                self.isGranted = trusted
                if trusted {
                    action()
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
