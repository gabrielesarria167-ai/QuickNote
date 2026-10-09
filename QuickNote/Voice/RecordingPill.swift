import AppKit
import SwiftUI

/// What the pill shows besides the recording itself: an error, for a few seconds.
@MainActor
@Observable
final class RecordingPillModel {
    var errorMessage: String?
}

/// Small floating pill that shows a recording in progress. It never becomes key: taking key from the
/// capture panel would make that panel save and close in the middle of a recording.
final class RecordingPill: NSPanel {
    private static let size = NSSize(width: 380, height: 118)

    private let model = RecordingPillModel()
    private var hideTask: Task<Void, Never>?

    init(recorder: VoiceRecorder, onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        contentView = FirstMouseHostingView(
            rootView: RecordingPillView(recorder: recorder, model: model, onStop: onStop, onCancel: onCancel)
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the pill for a recording, without taking focus from whatever you're in.
    func showRecording() {
        hideTask?.cancel()
        model.errorMessage = nil
        present()
    }

    /// Shows why a recording couldn't start, then hides itself after a few seconds.
    func showError(_ message: String) {
        hideTask?.cancel()
        model.errorMessage = message
        present()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        orderOut(nil)
        model.errorMessage = nil
    }

    private func present() {
        if !isVisible {
            setFrameOrigin(originOnActiveScreen())
        }
        orderFrontRegardless()
    }

    /// Horizontally centred, near the top of the screen under the mouse.
    private func originOnActiveScreen() -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return .zero }
        return NSPoint(
            x: frame.midX - Self.size.width / 2,
            y: frame.maxY - Self.size.height - 12
        )
    }
}

/// Lets the first click on the pill reach its buttons even though the pill is never the key window.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RecordingPillView: View {
    let recorder: VoiceRecorder
    let model: RecordingPillModel
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Group {
            if let message = model.errorMessage {
                errorBody(message)
            } else {
                recordingBody
            }
        }
        .padding(14)
        .frame(width: 380, height: 118)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var isFinishing: Bool { recorder.state == .finishing }

    private var recordingBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isFinishing {
                    ProgressView().controlSize(.small)
                } else {
                    PulsingDot()
                    LevelBars(level: recorder.level)
                }
                if let startedAt = recorder.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 0.5)) { context in
                        Text(Self.clock(context.date.timeIntervalSince(startedAt)))
                            .monospacedDigit()
                    }
                }
                Spacer()
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                }
                .help("Stop and save")
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .help("Discard")
            }
            .buttonStyle(.borderless)
            .disabled(isFinishing)

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(recorder.liveText.isEmpty || isFinishing ? .secondary : .primary)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

            Text("⌃⌥R to stop")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bodyText: String {
        if isFinishing { return "Saving…" }
        return recorder.liveText.isEmpty ? "Listening…" : recorder.liveText
    }

    private func errorBody(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mic.slash")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// `m:ss`
    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct PulsingDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.4
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .opacity(0.65 + 0.35 * sin(phase))
        }
    }
}

private struct LevelBars: View {
    let level: Double
    private let weights = [0.55, 0.85, 1.0, 0.7, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.secondary)
                    .frame(width: 3, height: 4 + 14 * level * weights[index])
            }
        }
        .frame(height: 18)
        .animation(.easeOut(duration: 0.1), value: level)
    }
}
