import Foundation

/// Recordings Gemini couldn't transcribe, kept in `Application Support/<bundle id>/Unsent Recordings`
/// (outside the temporary folder, which is emptied at launch) so the user can retry or keep them.
enum UnsentRecordings {
    static var folder: URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.gabrielesarria.quicknote", directoryHint: .isDirectory)
            .appending(path: "Unsent Recordings", directoryHint: .isDirectory)
    }

    /// A recording longer than this (seconds) is not believed when Gemini says nothing was said.
    static let longRecording: TimeInterval = 30

    /// Whether the recording should stay on disk after Gemini's answer. Only a failure keeps it.
    /// `.empty` is Gemini saying nothing was said, so there is nothing to keep, unless the recording is
    /// long or Apple's text was incomplete: then Gemini may be wrong and the audio is all there is.
    ///
    /// Pure logic with no AppKit dependency so it can be unit tested.
    static func shouldKeep(
        after result: Result<Transcription, GeminiError>,
        appleIncomplete: Bool = false,
        duration: TimeInterval = 0
    ) -> Bool {
        switch result {
        case .success: false
        case .failure(.empty): appleIncomplete || duration > longRecording
        case .failure: true
        }
    }

    /// Whether `url` is a file in `folder`.
    static func contains(_ url: URL, in folder: URL = UnsentRecordings.folder) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path
    }

    /// Whether to keep the recording when the user stops waiting for Gemini: yes if Apple's text
    /// is incomplete (its recognizer gave up), since the recording is then the only full copy.
    static func shouldKeepWhenStoppedWaiting(appleIncomplete: Bool) -> Bool {
        appleIncomplete
    }

    /// File name for a recording made at `date`: `2026-10-10 14.03.22.aac`, with ` 2`, ` 3`… added
    /// if `taken` already has it. No colons, which Finder shows as slashes.
    static func fileName(for date: Date, taken: Set<String> = []) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = formatter.string(from: date)
        var name = base + ".aac"
        var number = 2
        while taken.contains(name) {
            name = "\(base) \(number).aac"
            number += 1
        }
        return name
    }

    /// Moves a recording into the folder. Returns its new location, or nil if that failed (the file
    /// then stays where it was).
    static func move(_ url: URL, at date: Date = .now, into folder: URL = UnsentRecordings.folder) -> URL? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let taken = Set((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
            let destination = folder.appending(path: fileName(for: date, taken: taken))
            try manager.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// How many recordings are waiting.
    static func count(in folder: URL = UnsentRecordings.folder) -> Int {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return items.filter { $0.hasSuffix(".aac") }.count
    }
}
