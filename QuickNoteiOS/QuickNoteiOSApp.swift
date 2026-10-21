import SwiftData
import SwiftUI

@main
struct QuickNoteiOSApp: App {
    var body: some Scene {
        WindowGroup {
            CaptureView()
        }
        .modelContainer(for: Note.self)
    }
}
