import AppKit
import SwiftUI

/// What the pill shows besides the recording itself: an error, for a few seconds.
@MainActor
@Observable
final class RecordingPillModel {
    var error: VoiceRecorderError?
}

/// Small floating pill that shows a recording in progress. It never becomes key: taking key from the
/// capture panel would make that panel save and close in the middle of a recording.
final class RecordingPill: NSPanel {
    static let size = NSSize(width: 360, height: 100)

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
            rootView: RecordingPillView(
                recorder: recorder,
                model: model,
                onStop: onStop,
                onCancel: onCancel,
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the pill for a recording, without taking focus from whatever you're in. It goes just below
    /// `anchor` (the capture panel) if given, otherwise near the top of the screen.
    func showRecording(below anchor: NSRect?) {
        hideTask?.cancel()
        model.error = nil
        setFrameOrigin(origin(below: anchor))
        orderFrontRegardless()
    }

    /// Shows why a recording couldn't start or had to stop. Permission errors stay long enough to act
    /// on; the others go after a few seconds.
    func showError(_ error: VoiceRecorderError) {
        hideTask?.cancel()
        model.error = error
        if !isVisible {
            setFrameOrigin(origin(below: nil))
        }
        orderFrontRegardless()
        let seconds = error.settingsURL == nil ? 3.0 : 8.0
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        orderOut(nil)
        model.error = nil
    }

    private func origin(below anchor: NSRect?) -> NSPoint {
        let size = Self.size
        let mouse = NSEvent.mouseLocation
        let screen = anchor.flatMap { anchor in NSScreen.screens.first { $0.frame.intersects(anchor) } }
            ?? NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return .zero }

        var origin = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12)
        if let anchor {
            let below = anchor.minY - size.height - 8
            if below >= visible.minY {
                origin = NSPoint(x: anchor.midX - size.width / 2, y: below)
            }
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        return origin
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
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let error = model.error {
                errorBody(error)
            } else {
                recordingBody
            }
        }
        .padding(12)
        .frame(width: RecordingPill.size.width, height: RecordingPill.size.height)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var isBusy: Bool { recorder.state == .starting || recorder.state == .finishing }

    private var stateText: String {
        switch recorder.state {
        case .starting: "Starting…"
        case .finishing: "Saving…"
        default: "Recording"
        }
    }

    private var recordingBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, isActive: !reduceMotion)
                            .accessibilityHidden(true)
                        LevelBars(level: recorder.level)
                            .accessibilityHidden(true)
                    }
                    Text(stateText)
                        .font(.callout.weight(.medium))
                    if let startedAt = recorder.startedAt {
                        Text(startedAt, style: .timer)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Stop and save", systemImage: "stop.fill", action: onStop)
                    .help("Stop and save")
                    .disabled(isBusy)
                Button("Discard", systemImage: "xmark", action: onCancel)
                    .help(recorder.state == .starting ? "Cancel" : "Discard")
                    .disabled(recorder.state == .finishing)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(recorder.liveText.isEmpty ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            Text(recorder.state == .starting ? "✕ cancels" : "⌃⌥R saves · ✕ discards")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bodyText: String {
        if !recorder.liveText.isEmpty { return recorder.liveText.endingExcerpt() }
        return recorder.state == .recording ? "Listening…" : ""
    }

    private func errorBody(_ error: VoiceRecorderError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mic.slash")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(error.localizedDescription)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                if let url = error.settingsURL {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(url)
                        onDismiss()
                    }
                }
                Spacer()
                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .help("Dismiss")
            }
            .buttonStyle(.borderless)
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
