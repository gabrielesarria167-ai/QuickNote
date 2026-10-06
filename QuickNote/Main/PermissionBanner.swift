import SwiftUI

struct PermissionBanner: View {
    let permission: AccessibilityPermission

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "QuickNote"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("⌃⌥ shortcut is off")
                    .font(.headline)
                Text("Allow “\(appName)” under Privacy & Security → Accessibility so it can notice ⌃⌥ in other apps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Bundle.main.bundleURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Open System Settings") { permission.openSystemSettings() }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        .padding(12)
    }
}
