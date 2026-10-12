import AppKit
import SwiftData

/// Starts and stops voice recordings and decides where the transcript goes: appended to the note in
/// the capture panel or the main window, or saved as a new note.
///
/// With a Gemini key the recording is also kept as audio; after it stops, Gemini transcribes it and
/// titles it while the pill says "Transcribing…". The user can discard it (✕ twice), or keep Apple's
/// on-device text right away (■). A recording is never deleted unless it held no speech or the user
/// discarded it: if Gemini fails it moves to the Unsent Recordings folder, Apple's text is saved and
/// the pill offers Retry; if Gemini succeeds it moves to Recently Transcribed for a week, in case the
/// text turns out to be made up. On quit the same happens at once (`saveForQuit`). An answer
/// unrelated to what Apple heard (Gemini sometimes invents one) counts as a failure, `.mismatch`.
@MainActor
@Observable
final class VoiceCaptureController {
    /// A recording waiting for Gemini.
    private struct Pending {
        var apple: String
        var target: RecordTarget<Note>
        var error: VoiceRecorderError?
        var audioURL: URL
        var duration: TimeInterval
        /// A retry of a kept recording, from Unsent Recordings or Recently Transcribed. It keeps its
        /// sidecar wherever it goes, and stays put if the user stops waiting.
        var isRetry = false
        /// Apple's recognizer gave up, so `apple` lacks the end of the recording.
        var appleIncomplete = false
        /// What Apple heard, when that isn't `apple`: a retry saves no on-device text (the note already
        /// has it) but still checks Gemini's answer against it.
        var heardOverride: String?

        /// What Apple's recognizer heard, to check Gemini's answer against.
        var heard: String { heardOverride ?? apple }

        var kind: RecordingPillModel.Transcribing.Kind {
            isRetry ? .retry : appleIncomplete ? .appleIncomplete : .normal
        }
    }

    /// A recording left in Unsent Recordings, which Retry can send again.
    private struct Kept {
        var url: URL
        var duration: TimeInterval
        var target: RecordTarget<Note>
        var reason: KeptReason
        /// What Apple's recognizer heard of it, to check Gemini's answer against on Retry.
        var heard: String
        /// The file is in the Unsent Recordings folder. If moving it there failed it is still where it
        /// was, in the temporary folder, and the next launch tries again.
        var isSafe = true
    }

    private let container: ModelContainer
    private let capture: CapturePanelController
    private let openNote: OpenNoteTracker
    private let settings: VoiceSettings

    @ObservationIgnored private let recorder = VoiceRecorder()
    @ObservationIgnored private lazy var pill = RecordingPill(
        recorder: recorder,
        onStop: { [weak self] in self?.stopButtonPressed() },
        onCancel: { [weak self] in self?.cancelButtonPressed() },
        onOpenSettings: { [weak self] in self?.openSettings() },
        onRetry: { [weak self] in self?.retry() },
        onShowInFinder: { [weak self] in self?.showKeptRecordingInFinder() }
    )
    @ObservationIgnored private let openSettings: () -> Void
    /// Gemini's transcription of the last recording, while it runs.
    @ObservationIgnored private var transcribeTask: Task<Void, Never>?
    /// What is needed to finish the recording that Gemini is transcribing.
    @ObservationIgnored private var pending: Pending?
    /// The recording the pill's Retry button would send.
    @ObservationIgnored private var lastKept: Kept?
    /// "Transcribe All", while it goes through the unsent recordings.
    @ObservationIgnored private var batchTask: Task<Void, Never>?
    /// ✕ needs two presses while transcribing.
    @ObservationIgnored private var confirmDiscard = ConfirmPress()

    /// Chosen once, when the recording starts.
    @ObservationIgnored private var target = RecordTarget<Note>.newNote
    /// Set as soon as a stop is requested; the recorder only changes state a moment later.
    @ObservationIgnored private var isStopping = false
    /// Counts starts and cancels, so a start that was cancelled before it began can tell.
    @ObservationIgnored private var startID = 0
    /// Set as soon as a start is requested; the recorder only changes state a moment later.
    private var isStarting = false

    /// The note most recently created from a recording, so the main window can select it.
    private(set) var lastCreatedNote: Note?

    /// Gemini is transcribing a recording.
    private(set) var isTranscribing = false

    /// The recordings waiting in the Unsent Recordings folder, oldest first. Updated by `refreshUnsentCount()`.
    private(set) var unsent: [UnsentRecordings.Recording] = []

    /// How many recordings wait in the Unsent Recordings folder.
    var unsentCount: Int { unsent.count }

    /// The recordings transcribed in the last week, newest first. Updated by `refreshUnsentCount()`.
    private(set) var recentlyTranscribed: [UnsentRecordings.Recording] = []

    /// True from the first ⌃⌥R until the transcript is saved, including the wait for Gemini.
    var isRecording: Bool { isStarting || recorder.state != .idle || isTranscribing }

    /// `openSettings` shows the Settings window; the pill's "Open Settings" button calls it.
    init(
        container: ModelContainer,
        capture: CapturePanelController,
        openNote: OpenNoteTracker,
        settings: VoiceSettings,
        openSettings: @escaping () -> Void
    ) {
        self.container = container
        self.capture = capture
        self.openNote = openNote
        self.settings = settings
        self.openSettings = openSettings
        SaveNotifier.shared.activate()
        recorder.onStopRequested = { [weak self] error in self?.finish(error: error) }
    }

    /// Lists the files in Unsent Recordings and Recently Transcribed (reads small sidecars; opens an
    /// audio file only when its sidecar is missing), after deleting transcribed ones older than a week.
    /// Called when the app comes to the front.
    func refreshUnsentCount() {
        unsent = UnsentRecordings.list()
        // Not the one being transcribed again right now.
        RecentlyTranscribed.purge(sparing: pending?.audioURL)
        recentlyTranscribed = UnsentRecordings.list(in: RecentlyTranscribed.folder).reversed()
    }

    /// Opens the Unsent Recordings folder in Finder.
    func showUnsentRecordings() {
        NSWorkspace.shared.open(UnsentRecordings.folder)
    }

    /// Opens the Recently Transcribed folder in Finder.
    func showRecentlyTranscribed() {
        NSWorkspace.shared.open(RecentlyTranscribed.folder)
    }

    /// ⌃⌥R. While Gemini is transcribing it only makes the pill pulse: that recording is finished and
    /// waits for its title and text.
    func toggle() {
        if isTranscribing {
            pill.flash()
        } else if isStarting || recorder.state == .starting {
            // Still waiting for a permission prompt: abandon it.
            cancel()
        } else if recorder.state == .idle {
            start()
        } else {
            finish()
        }
    }

    /// Starts a recording. `preferNote` (the note selected in the main window) wins over wherever the
    /// transcript would otherwise go.
    func start(preferNote: Note? = nil) {
        guard !isRecording else { return }
        target = chooseTarget(preferNote: preferNote)
        lastKept = nil
        isStopping = false
        isStarting = true
        startID += 1
        let id = startID
        // Shown right away: a permission prompt can keep the first start waiting a while.
        pill.showRecording(below: capture.frame)
        // Looks the key up without reading it, so it can't ask the user for anything.
        settings.refreshKeyState()
        let recordAudio = settings.hasGeminiKey
        let language = settings.onDeviceLanguage
        Task {
            guard id == startID else { return }
            do {
                try await recorder.start(recordAudio: recordAudio, language: language)
                // After the microphone and speech prompts, so they don't pile up.
                SaveNotifier.shared.requestPermission()
            } catch is CancellationError {
                // Cancelled while waiting for permission; nothing to show.
            } catch let error as VoiceRecorderError {
                pill.showError(error)
            } catch {
                pill.dismiss()
            }
            if id == startID { isStarting = false }
        }
    }

    private func chooseTarget(preferNote: Note?) -> RecordTarget<Note> {
        let keyEditorNote = openNote.window?.isKeyWindow == true ? openNote.note : nil
        let panel = capture.isOpen ? (session: capture.session, note: capture.shownNote) : nil
        return RecordTarget.choose(preferred: preferNote, panel: panel, keyEditorNote: keyEditorNote)
    }

    /// Stops listening, then saves what was said: Gemini's transcript and title if there is a key and
    /// it works, otherwise Apple's text. If the recording had to stop because of `error`, the pill
    /// then says why.
    private func finish(error: VoiceRecorderError? = nil) {
        guard recorder.state == .recording, !isStopping else { return }
        isStopping = true
        // Chosen when the recording started; copied before the first await.
        let target = target
        Task {
            let recording = await recorder.stop()
            isStopping = false

            guard let audioURL = recording.audioURL else {
                conclude(gemini: nil, apple: recording.text, target: target, error: error, kept: nil)
                return
            }
            var key: String?
            var keyUnreadable = false
            // The key is read only now, and only if there is something worth sending.
            if TranscriptChoice.shouldTranscribe(hasAudio: true, duration: recording.duration, hasKey: settings.hasGeminiKey) {
                do {
                    key = try settings.readKey()
                } catch {
                    keyUnreadable = true
                }
            }
            if let key {
                beginTranscription(
                    Pending(
                        apple: recording.text, target: target, error: error, audioURL: audioURL,
                        duration: recording.duration, appleIncomplete: recording.appleIncomplete
                    ),
                    key: key
                )
            } else if keyUnreadable {
                let kept = keep(audioURL, duration: recording.duration, target: target, heard: recording.text, reason: .keyUnreadable)
                conclude(gemini: nil, apple: recording.text, target: target, error: error, kept: kept)
            } else {
                // Too short to send, or the key is gone: nothing worth keeping.
                UnsentRecordings.remove(audioURL)
                conclude(gemini: nil, apple: recording.text, target: target, error: error, kept: nil)
            }
        }
    }

    /// Sends the recording to Gemini and finishes the note when it answers. The pill shows the wait.
    private func beginTranscription(_ pending: Pending, key: String) {
        self.pending = pending
        isTranscribing = true
        confirmDiscard.reset()
        pill.showTranscribing(kind: pending.kind)
        let model = settings.model
        transcribeTask = Task {
            let result: Result<Transcription, GeminiError>
            do {
                let transcriber = GeminiTranscriber()
                var transcription = try await transcriber.transcribe(
                    audioURL: pending.audioURL, duration: pending.duration, apiKey: key, model: model
                )
                // Far fewer words than Apple heard (the answer probably stopped early), or nothing like
                // what it heard (Gemini made it up). Ask once more and take the better answer; if the
                // retry fails the first answer stands.
                if TranscriptChoice.looksCutShort(gemini: transcription.transcript, apple: pending.heard)
                    || TranscriptChoice.looksUnrelated(gemini: transcription.transcript, apple: pending.heard),
                   let again = try? await transcriber.transcribe(
                       audioURL: pending.audioURL, duration: pending.duration, apiKey: key, model: model
                   ) {
                    transcription = TranscriptChoice.better(transcription, again, apple: pending.heard)
                }
                // Still unrelated: never saved in place of Apple's text, and the recording is kept.
                result = TranscriptChoice.looksUnrelated(gemini: transcription.transcript, apple: pending.heard)
                    ? .failure(.mismatch)
                    : .success(transcription)
            } catch let error as GeminiError {
                result = .failure(error)
            } catch {
                // Cancelled: whoever did that has already dealt with the recording.
                return
            }
            guard !Task.isCancelled, let pending = self.pending else { return }
            self.pending = nil
            isTranscribing = false
            transcribeTask = nil
            settle(result, for: pending)
        }
    }

    /// Gemini answered. Keeps or deletes the audio, then saves the text and tells the user what they
    /// need to know.
    private func settle(_ result: Result<Transcription, GeminiError>, for pending: Pending) {
        var kept: Kept?
        var retained: URL?
        if UnsentRecordings.shouldKeep(after: result, appleIncomplete: pending.appleIncomplete || pending.isRetry, duration: pending.duration),
           case .failure(let error) = result {
            kept = keep(pending.audioURL, duration: pending.duration, target: pending.target, heard: pending.heard, reason: .gemini(error))
            if error == .mismatch, let url = kept?.url {
                // Checked once. If the check was wrong, Retry must be able to get past it; the audio
                // of whatever comes back is kept for a week anyway.
                UnsentRecordings.forgetAppleText(of: url)
                kept?.heard = ""
            }
        } else if case .success(let transcription) = result,
                  TranscriptChoice.looksCutShort(gemini: transcription.transcript, apple: pending.apple) {
            // Still short after asking twice: the longer text is saved, and the audio stays in Unsent
            // Recordings. Not for a retry (`apple` is empty): its text is already in the note, and
            // staying in Unsent would add it again on every resume.
            kept = keep(pending.audioURL, duration: pending.duration, target: pending.target, heard: pending.heard, reason: .incomplete)
        } else if case .success = result {
            // Kept for a week: Gemini may have made the text up, and that isn't always detectable.
            // A retried recording brings its own sidecar.
            // If the move fails a new recording stays in the temporary folder until the next launch.
            let metadata = pending.isRetry ? nil : metadata(duration: pending.duration, target: pending.target, heard: pending.heard)
            retained = RecentlyTranscribed.keep(pending.audioURL, metadata: metadata)
        } else {
            UnsentRecordings.remove(pending.audioURL)
        }
        let created = lastCreatedNote
        conclude(gemini: result, apple: pending.apple, target: pending.target, error: pending.error, kept: kept)
        // The text became a new note: "Transcribe Again" should add to that note, not make another.
        if let retained, let note = lastCreatedNote, note !== created {
            UnsentRecordings.setNoteID(note.persistentModelID, of: retained)
            refreshUnsentCount()
        }
    }

    /// Picks the text, saves it and tells the user anything they need to know. A notice about a kept
    /// recording comes before a recorder error: it is the one that says nothing was lost.
    private func conclude(
        gemini: Result<Transcription, GeminiError>?,
        apple: String,
        target: RecordTarget<Note>,
        error: VoiceRecorderError?,
        kept: Kept?
    ) {
        let choice = TranscriptChoice.choose(gemini: gemini, apple: apple)
        let composed = VoiceNoteText.compose(title: choice.title, transcript: choice.text)
        let saved = save(composed, to: target)
        if saved == .elsewhere {
            SaveNotifier.shared.notifySaved(title: choice.title, text: choice.text, onDevice: choice.notice != nil)
        }
        lastKept = kept
        refreshUnsentCount()

        let nothingHeard = composed.isEmpty
        if let kept {
            pill.showNotice(
                GeminiNotice.keptMessage(for: kept.reason, savedOnDevice: !nothingHeard, recordingKept: kept.isSafe),
                opensSettings: GeminiNotice.offersSettings(for: kept.reason),
                keptRecording: true,
                // A second answer would be added to the note as a duplicate transcript.
                canRetry: kept.reason != .incomplete
            )
        } else if let error {
            pill.showError(error == .recognitionStopped && nothingHeard ? .recognitionNotWorking : error)
        } else if let notice = choice.notice, !(notice == .empty && nothingHeard) {
            pill.showNotice(
                GeminiNotice.message(for: notice, savedOnDevice: !nothingHeard),
                opensSettings: GeminiNotice.offersSettings(for: notice)
            )
        } else {
            pill.dismiss()
        }
    }

    /// The pill's ■: saves the recording, or while Gemini is working stops waiting for it.
    private func stopButtonPressed() {
        if isTranscribing {
            stopWaiting()
        } else {
            finish()
        }
    }

    /// The pill's ✕: discards the recording. While Gemini works it takes a second press within three
    /// seconds, since there is no way back. A retry just stops: the recording stays where it is.
    private func cancelButtonPressed() {
        guard isTranscribing else {
            cancel()
            return
        }
        guard let pending else { return }
        if pending.isRetry {
            stopWaiting()
        } else if confirmDiscard.press(at: ProcessInfo.processInfo.systemUptime) {
            endTranscription()
            UnsentRecordings.remove(pending.audioURL)
            pill.dismiss()
        } else {
            pill.armDiscard()
        }
    }

    /// Stops waiting for Gemini. Apple's text is saved without a title; the recording is deleted if
    /// that text is all of it, and kept in Unsent Recordings if Apple's recognizer had given up. For a
    /// retry nothing is saved and the recording stays.
    private func stopWaiting() {
        guard let pending else { return }
        endTranscription()
        guard !pending.isRetry else {
            pill.dismiss()
            return
        }
        var kept: Kept?
        if UnsentRecordings.shouldKeepWhenStoppedWaiting(appleIncomplete: pending.appleIncomplete) {
            kept = keep(pending.audioURL, duration: pending.duration, target: pending.target, heard: pending.heard, reason: .stoppedWaiting)
        } else {
            UnsentRecordings.remove(pending.audioURL)
        }
        conclude(gemini: nil, apple: pending.apple, target: pending.target, error: pending.error, kept: kept)
    }

    /// Cancels the request. What happens to the audio file is up to the caller.
    private func endTranscription() {
        transcribeTask?.cancel()
        transcribeTask = nil
        isTranscribing = false
        pending = nil
    }

    /// Moves a recording to Unsent Recordings (it may already be there). One from Recently Transcribed
    /// brings its sidecar, so it keeps its date, its note and its name.
    private func keep(_ url: URL, duration: TimeInterval, target: RecordTarget<Note>, heard: String, reason: KeptReason) -> Kept {
        if UnsentRecordings.contains(url) {
            return Kept(url: url, duration: duration, target: target, reason: reason, heard: heard)
        }
        let oldSidecar = UnsentRecordings.sidecarURL(for: url)
        var existing = (try? Data(contentsOf: oldSidecar)).flatMap(UnsentRecordings.decode)
        if existing != nil, heard.isEmpty { existing?.appleText = nil }
        let moved = UnsentRecordings.move(
            url,
            metadata: existing ?? metadata(duration: duration, target: reason == .incomplete ? .newNote : target, heard: heard)
        )
        if moved != nil { try? FileManager.default.removeItem(at: oldSidecar) }
        return Kept(url: moved ?? url, duration: duration, target: target, reason: reason, heard: heard, isSafe: moved != nil)
    }

    /// What the sidecar of a recording made now says.
    private func metadata(duration: TimeInterval, target: RecordTarget<Note>, heard: String, date: Date = .now) -> UnsentRecordings.Metadata {
        // A note that was never saved has a temporary ID, which means nothing after a relaunch.
        if container.mainContext.hasChanges { try? container.mainContext.save() }
        let note: Note? = switch target {
        case .panel(_, let note): note
        case .openNote(let note): note
        case .newNote: nil
        }
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        return UnsentRecordings.Metadata(
            duration: duration, date: date.addingTimeInterval(-duration), noteID: note?.persistentModelID,
            appleText: heard.isEmpty ? nil : heard
        )
    }

    /// The note with this identifier, if it still exists.
    private func note(with id: PersistentIdentifier) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.persistentModelID == id })
        descriptor.fetchLimit = 1
        return try? container.mainContext.fetch(descriptor).first
    }

    /// The pill's Retry: sends the kept recording to Gemini again. Not offered for `.incomplete`: that
    /// note already holds Gemini's text, and a second answer would only be a duplicate under it. The text goes to the same target as
    /// before, through the usual fallbacks; a note that already got Apple's text gets Gemini's as its
    /// own `# Title` block below it (a new recording's target `.newNote` becomes a second note).
    private func retry() {
        guard let kept = lastKept, kept.reason != .incomplete else { return }
        _ = retry(kept)
    }

    /// Sends a kept recording to Gemini. Returns false if that couldn't start (something is running, or
    /// the key is missing or unreadable, which the pill then says).
    private func retry(_ kept: Kept) -> Bool {
        guard !isRecording else { return false }
        let key: String?
        do {
            key = try settings.readKey()
        } catch {
            lastKept = Kept(url: kept.url, duration: kept.duration, target: kept.target, reason: .keyUnreadable, heard: kept.heard, isSafe: kept.isSafe)
            pill.showNotice(
                GeminiNotice.keptMessage(for: .keyUnreadable, savedOnDevice: false, recordingKept: kept.isSafe),
                opensSettings: false,
                keptRecording: true
            )
            return false
        }
        guard let key else {
            lastKept = Kept(url: kept.url, duration: kept.duration, target: kept.target, reason: .gemini(.badKey), heard: kept.heard, isSafe: kept.isSafe)
            pill.showNotice(
                GeminiNotice.keptMessage(for: .gemini(.badKey), savedOnDevice: false, recordingKept: kept.isSafe),
                opensSettings: true,
                keptRecording: true
            )
            return false
        }
        lastKept = kept
        beginTranscription(
            Pending(
                apple: "", target: kept.target, error: nil, audioURL: kept.url, duration: kept.duration,
                isRetry: true, heardOverride: kept.heard
            ),
            key: key
        )
        return true
    }

    /// Transcribes a recording from the Unsent Recordings list. The text goes to the note it was made
    /// for if that still exists, otherwise to a new note.
    func resume(_ recording: UnsentRecordings.Recording) {
        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            refreshUnsentCount()
            return
        }
        _ = retry(kept(for: recording))
    }

    /// Transcribes every unsent recording, one after another, oldest first. Stops at the first one
    /// that doesn't get transcribed.
    func resumeAll() {
        guard !isRecording, batchTask == nil else { return }
        batchTask = Task {
            defer { batchTask = nil }
            for recording in UnsentRecordings.list() {
                guard FileManager.default.fileExists(atPath: recording.url.path) else {
                    refreshUnsentCount()
                    continue
                }
                guard !Task.isCancelled, retry(kept(for: recording)), let task = transcribeTask else { return }
                await task.value
                // Still there: it failed, or the user stopped waiting.
                if FileManager.default.fileExists(atPath: recording.url.path) { return }
            }
        }
    }

    /// Sends a recording from Recently Transcribed to Gemini again, for a transcript that came out
    /// wrong. The new text goes below the old one in the same note (or into a new note), and isn't
    /// checked against Apple's text: the user has already judged the last answer.
    func transcribeAgain(_ recording: UnsentRecordings.Recording) {
        guard FileManager.default.fileExists(atPath: recording.url.path) else {
            refreshUnsentCount()
            return
        }
        var kept = kept(for: recording)
        kept.heard = ""
        _ = retry(kept)
    }

    private func kept(for recording: UnsentRecordings.Recording) -> Kept {
        let target: RecordTarget<Note> = recording.noteID.flatMap { note(with: $0) }.map { .openNote($0) } ?? .newNote
        return Kept(url: recording.url, duration: recording.duration, target: target, reason: .stoppedWaiting, heard: recording.appleText ?? "")
    }

    private func showKeptRecordingInFinder() {
        guard let url = lastKept?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// The app is quitting. Saves whatever there is right now: Apple's text goes to its target, and a
    /// recording still on its way to Gemini moves to Unsent Recordings, so nothing is lost.
    func saveForQuit() {
        batchTask?.cancel()
        if let pending {
            endTranscription()
            if !pending.isRetry {
                _ = UnsentRecordings.move(pending.audioURL, metadata: metadata(duration: pending.duration, target: pending.target, heard: pending.heard))
                save(VoiceNoteText.compose(title: nil, transcript: pending.apple), to: pending.target)
            }
        } else if recorder.state == .recording || recorder.state == .finishing {
            let recording = recorder.stopNow()
            if let url = recording.audioURL {
                if recording.duration >= TranscriptChoice.minimumAudioDuration {
                    _ = UnsentRecordings.move(url, metadata: metadata(duration: recording.duration, target: target, heard: recording.text))
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            save(recording.text, to: target)
        } else if isRecording {
            cancel()
        }
        // The capture panel writes its draft (which now holds the text) when it closes.
        if capture.isOpen {
            capture.commit()
        }
        pill.dismiss()
    }

    private func cancel() {
        startID += 1
        isStarting = false
        recorder.cancel()
        pill.dismiss()
    }

    /// Where `save` put the text.
    private enum Saved {
        case nothing
        /// Into the capture panel, which shows it to the user.
        case inPanel
        /// Into a note that isn't on screen in the panel.
        case elsewhere
    }

    @discardableResult
    private func save(_ transcript: String, to target: RecordTarget<Note>) -> Saved {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .nothing }

        switch target {
        case .panel(let session, let note):
            // The panel saves itself when it closes. If it was closed (clicking away, or a permission
            // prompt taking focus) or reopened since, the text still goes to the note it showed,
            // or becomes a new note if it showed the new one.
            if capture.isOpen, capture.session == session {
                capture.appendTranscript(text, to: note)
                return .inPanel
            }
            if let note, append(text, to: note) { return capture.isShowing(note) ? .inPanel : .elsewhere }
        case .openNote(let note):
            if append(text, to: note) { return capture.isShowing(note) ? .inPanel : .elsewhere }
        case .newNote:
            break
        }

        let note = Note(text: text)
        container.mainContext.insert(note)
        try? container.mainContext.save()
        lastCreatedNote = note
        return .elsewhere
    }

    /// Adds the text to an existing note. Returns false if the note is gone.
    private func append(_ text: String, to note: Note) -> Bool {
        guard note.modelContext != nil, !note.isDeleted else { return false }
        if capture.isShowing(note) {
            // The editor in the panel has this note's text; the panel writes it back when it closes.
            capture.appendTranscript(text, to: note)
        } else {
            note.text = note.text.appendingParagraph(text)
            note.updatedAt = .now
            try? container.mainContext.save()
        }
        return true
    }
}
