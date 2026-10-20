import AppKit
import UserNotifications

/// Tells the user, with a system notification, that a voice note has been transcribed and saved: the
/// recording is often made while another app is in front, and nothing else says when it is done.
///
/// Permission is asked for the first time a recording starts, not at launch. The delegate makes the
/// banner show even while QuickNote is the active app; clicking it brings QuickNote forward.
final class SaveNotifier: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = SaveNotifier()

    /// Brings up the notes window when a banner is clicked; set by the app delegate.
    @MainActor static var showMainWindow: (() -> Void)?

    /// How much of the text the banner shows when there is no title.
    static let previewLength = 80

    private var center: UNUserNotificationCenter { .current() }

    /// Becomes the delegate, so a banner clicked after a relaunch still reaches the app.
    func activate() {
        center.delegate = self
    }

    /// Asks for permission to show banners and play a sound; does nothing once the user has answered.
    func requestPermission() {
        activate()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// "Voice note saved", with the title or the start of the text. `onDevice` says Apple's text was
    /// saved because Gemini's wasn't used.
    func notifySaved(title: String?, text: String, onDevice: Bool) {
        let content = UNMutableNotificationContent()
        content.title = onDevice ? "Voice note saved (on-device transcript)" : "Voice note saved"
        content.body = Self.preview(title: title, text: text)
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { _ in }
    }

    /// The title if there is one, else the first `previewLength` characters of the text on one line.
    static func preview(title: String?, text: String) -> String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.count > previewLength else { return line }
        return line.prefix(previewLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            Self.showMainWindow?()
        }
    }
}
