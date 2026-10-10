import AppKit
import SwiftUI

/// What the pill shows besides the recording itself: an error or a notice for a few seconds, or
/// the wait for Gemini.
@MainActor
@Observable
final class RecordingPillModel {
    struct Notice: Equatable {
        var message: String
        /// Offers a button that opens the Settings window.
        var opensSettings: Bool
        /// The recording was kept: the notice stays until dismissed and offers Retry and Show in Finder.
        var keptRecording: Bool
        /// A kept recording can be sent to Gemini again with Retry.
        var canRetry = true
    }

    /// Gemini is transcribing the recording.
    struct Transcribing: Equatable {
        enum Kind {
            /// A fresh recording; ■ keeps Apple's text.
            case normal
            /// Apple's text is incomplete; ■ keeps the recording instead.
            case appleIncomplete
            /// A retry of a kept recording; ■ and ✕ both stop it and leave the recording where it is.
            case retry
        }

        var kind: Kind
    }

    var error: VoiceRecorderError?
    var notice: Notice?
    var transcribing: Transcribing?
    /// ✕ was pressed once while transcribing; pressing it again discards the recording.
    var discardArmed = false
    /// Counts the times the pill was asked to draw attention to itself.
    var flashCount = 0
}

/// Small floating pill that shows a recording in progress. It never becomes key: taking key from the
/// capture panel would make that panel save and close in the middle of a recording.
final class RecordingPill: NSPanel {
    static let size = NSSize(width: 360, height: 100)

    private let model = RecordingPillModel()
    private var hideTask: Task<Void, Never>?
    private var disarmTask: Task<Void, Never>?
    /// Set while the app itself places the pill, so that move isn't taken for the user's.
    private var isPlacing = false
    /// The user pressed the mouse on the pill since it was last placed, so a move may be theirs.
    private var userTouched = false

    /// Where the user last left the pill (its bottom left corner), as an array of two numbers.
    private static let originKey = "recordingPillOrigin"

    /// `onStop` is the ■ button: it saves a recording, or while Gemini transcribes it keeps the
    /// on-device text. `onCancel` is ✕: it discards the recording or the transcription.
    init(
        recorder: VoiceRecorder,
        onStop: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onRetry: @escaping () -> Void,
        onShowInFinder: @escaping () -> Void
    ) {
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
        // Dragging the background moves the pill; the buttons still take their clicks.
        isMovableByWindowBackground = true
        // The pill lives as long as the app, so the observer is never removed.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: self, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowMoved() }
        }
        contentView = FirstMouseHostingView(
            rootView: RecordingPillView(
                recorder: recorder,
                model: model,
                onStop: onStop,
                onCancel: onCancel,
                onOpenSettings: onOpenSettings,
                onRetry: onRetry,
                onShowInFinder: onShowInFinder,
                onDismiss: { [weak self] in self?.dismiss() },
                onResetPosition: { [weak self] in self?.resetPosition() }
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the pill for a recording, without taking focus from whatever you're in. It goes just below
    /// `anchor` (the capture panel) if given, otherwise near the top of the screen.
    func showRecording(below anchor: NSRect?) {
        hideTask?.cancel()
        clearContent()
        place(at: origin(below: anchor))
        orderFrontRegardless()
    }

    /// Shows that Gemini is transcribing the recording.
    func showTranscribing(kind: RecordingPillModel.Transcribing.Kind) {
        hideTask?.cancel()
        clearContent()
        model.transcribing = RecordingPillModel.Transcribing(kind: kind)
        if !isVisible {
            place(at: origin(below: nil))
        }
        orderFrontRegardless()
    }

    /// Says why Gemini's answer wasn't used. A notice about a kept recording stays until dismissed;
    /// one with a button for the Settings window stays longer than a plain one.
    func showNotice(_ message: String, opensSettings: Bool, keptRecording: Bool = false, canRetry: Bool = true) {
        hideTask?.cancel()
        clearContent()
        model.notice = RecordingPillModel.Notice(message: message, opensSettings: opensSettings, keptRecording: keptRecording, canRetry: canRetry)
        if !isVisible {
            place(at: origin(below: nil))
        }
        orderFrontRegardless()
        guard !keptRecording else { return }
        let seconds = opensSettings ? 8.0 : 5.0
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Shows why a recording couldn't start or had to stop. Permission errors stay long enough to act
    /// on; the others go after a few seconds.
    func showError(_ error: VoiceRecorderError) {
        hideTask?.cancel()
        clearContent()
        model.error = error
        if !isVisible {
            place(at: origin(below: nil))
        }
        orderFrontRegardless()
        let seconds = error.settingsURL == nil ? 3.0 : 8.0
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// Asks for the second ✕ press that discards a recording; forgotten after three seconds.
    func armDiscard() {
        model.discardArmed = true
        disarmTask?.cancel()
        disarmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.model.discardArmed = false
        }
    }

    /// A quick pulse, to say "not now" when a shortcut is pressed while the pill is busy.
    func flash() {
        model.flashCount += 1
    }

    func dismiss() {
        hideTask?.cancel()
        orderOut(nil)
        userTouched = false
        clearContent()
    }

    private func clearContent() {
        disarmTask?.cancel()
        model.error = nil
        model.notice = nil
        model.transcribing = nil
        model.discardArmed = false
    }

    /// Forgets the spot the user chose and puts the pill back where it starts.
    private func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Self.originKey)
        place(at: origin(below: nil, usingSaved: false))
    }

    /// Moves the pill without remembering that as the user's choice.
    private func place(at origin: NSPoint) {
        userTouched = false
        isPlacing = true
        setFrameOrigin(origin)
        isPlacing = false
    }

    /// Notes that the user pressed the mouse on the pill; see `userTouched`.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { userTouched = true }
        super.sendEvent(event)
    }

    private func windowMoved() {
        // Only a drag by the user counts, not a move the system makes (a screen change, say). The
        // notification can arrive after the mouse is released, so the press is what is tracked.
        guard userTouched, !isPlacing, isVisible else { return }
        UserDefaults.standard.set([frame.origin.x, frame.origin.y], forKey: Self.originKey)
    }

    /// The origin the user left the pill at, moved onto the nearest screen if it lies outside them.
    private func savedOrigin() -> NSPoint? {
        guard let values = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], values.count == 2 else {
            return nil
        }
        let origin = NSPoint(x: values[0], y: values[1])
        // Pulled back inside the nearest screen, so a spot on an unplugged display isn't lost.
        let center = NSPoint(x: origin.x + Self.size.width / 2, y: origin.y + Self.size.height / 2)
        let nearest = NSScreen.screens.min { distance(from: center, to: $0.visibleFrame) < distance(from: center, to: $1.visibleFrame) }
        guard let visible = nearest?.visibleFrame else { return nil }
        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - Self.size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - Self.size.height)
        )
    }

    private func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func origin(below anchor: NSRect?, usingSaved: Bool = true) -> NSPoint {
        if usingSaved, let saved = savedOrigin() { return saved }
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
    let onOpenSettings: () -> Void
    let onRetry: () -> Void
    let onShowInFinder: () -> Void
    let onDismiss: () -> Void
    let onResetPosition: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Group {
            if let error = model.error {
                errorBody(error)
            } else if let notice = model.notice {
                noticeBody(notice)
            } else {
                recordingBody
            }
        }
        .padding(12)
        .frame(width: RecordingPill.size.width, height: RecordingPill.size.height)
        .background {
            // Double-clicking the pill's own background (not a button) puts it back in its default spot.
            Rectangle()
                .fill(.clear)
                .contentShape(.rect)
                .onTapGesture(count: 2, perform: onResetPosition)
        }
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .scaleEffect(pulsing ? 1.04 : 1)
        .onChange(of: model.flashCount) {
            guard !reduceMotion else { return }
            pulsing = true
            withAnimation(.easeOut(duration: 0.3)) { pulsing = false }
        }
    }

    private var isTranscribing: Bool { model.transcribing != nil }

    private var stopLabel: String {
        switch model.transcribing?.kind {
        case nil: "Stop and save"
        case .normal: "Use on-device text"
        case .appleIncomplete, .retry: "Stop waiting — keep the recording"
        }
    }

    private var isBusy: Bool {
        !isTranscribing && (recorder.state == .starting || recorder.state == .finishing)
    }

    private var stateText: String {
        if isTranscribing { return "Transcribing…" }
        return switch recorder.state {
        case .starting: "Starting…"
        case .finishing: "Saving…"
        default: "Recording"
        }
    }

    private var recordingBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    if isBusy || isTranscribing {
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
                Button(stopLabel, systemImage: "stop.fill", action: onStop)
                    .help(stopLabel)
                    .disabled(isBusy)
                Button("Discard", systemImage: "xmark", action: onCancel)
                    .help(recorder.state == .starting ? "Cancel" : "Discard")
                    .disabled(!isTranscribing && recorder.state == .finishing)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Text(bodyText)
                .font(.callout)
                .foregroundStyle(bodyIsPlaceholder ? .secondary : .primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)

            Text(hintText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bodyText: String {
        if isTranscribing { return "Waiting for Gemini…" }
        if recorder.appleStopped { return "Listening — text after you stop" }
        if !recorder.liveText.isEmpty { return recorder.liveText.endingExcerpt() }
        return recorder.state == .recording ? "Listening…" : ""
    }

    private var bodyIsPlaceholder: Bool {
        if isTranscribing { return true }
        return recorder.appleStopped || recorder.liveText.isEmpty
    }

    private var hintText: String {
        switch model.transcribing?.kind {
        case .normal:
            return model.discardArmed ? "Press ✕ again to discard" : "✕ discards · ■ keeps on-device text"
        case .appleIncomplete:
            return model.discardArmed ? "Press ✕ again to discard" : "✕ discards · ■ stops waiting, keeps the recording"
        case .retry:
            return "✕ or ■ stops · the recording stays saved"
        case nil:
            break
        }
        return recorder.state == .starting ? "✕ cancels" : "⌃⌥R saves · ✕ discards"
    }

    private func noticeBody(_ notice: RecordingPillModel.Notice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(notice.message)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            HStack {
                if notice.keptRecording {
                    if notice.canRetry {
                        Button("Retry", action: onRetry)
                    }
                    Button("Show in Finder", action: onShowInFinder)
                }
                if notice.opensSettings {
                    Button("Open Settings") {
                        onOpenSettings()
                        // A kept recording's notice stays, so Retry is there once the key is fixed.
                        if !notice.keptRecording { onDismiss() }
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
