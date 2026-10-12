import AVFoundation
import Foundation
import SwiftData

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

    /// File name for a recording made at `date`: `2026-10-10 14.03.22.flac`, with ` 2`, ` 3`… added
    /// if `taken` already has it. No colons, which Finder shows as slashes. `fileExtension` is the
    /// recording's own (flac, or aac for the fallback format).
    static func fileName(for date: Date, taken: Set<String> = [], fileExtension: String = "aac") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = formatter.string(from: date)
        var name = "\(base).\(fileExtension)"
        var number = 2
        while taken.contains(name) {
            name = "\(base) \(number).\(fileExtension)"
            number += 1
        }
        return name
    }

    /// What is known about a recording, stored next to it in a JSON file with the same base name.
    struct Metadata: Codable, Equatable {
        /// Length in seconds.
        var duration: TimeInterval
        /// When it was recorded.
        var date: Date
        /// The note it belonged to, if any; it survives a relaunch.
        var noteID: PersistentIdentifier?
        /// What Apple's recognizer heard, so a retry can tell an invented answer from Gemini. Nil in
        /// sidecars written before it was kept.
        var appleText: String? = nil
    }

    /// A recording in the folder. `noteID` is nil for a new note or when nothing is known.
    struct Recording: Equatable {
        var url: URL
        var date: Date
        var duration: TimeInterval
        var noteID: PersistentIdentifier?
        /// What Apple's recognizer heard, if known.
        var appleText: String? = nil
    }

    private static let audioExtensions: Set<String> = ["flac", "aac"]

    /// Whether the file is a recording rather than a sidecar or a stray file.
    static func isRecording(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension)
    }

    /// Where the sidecar of `recording` lives: the same name with `.json`.
    static func sidecarURL(for recording: URL) -> URL {
        recording.deletingPathExtension().appendingPathExtension("json")
    }

    static func encode(_ metadata: Metadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(metadata)
    }

    /// Nil if the data isn't a sidecar.
    static func decode(_ data: Data) -> Metadata? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Metadata.self, from: data)
    }

    /// Writes the sidecar of `recording`. A failure is ignored: the recording is then listed with
    /// what the file itself says.
    static func writeSidecar(_ metadata: Metadata, for recording: URL) {
        guard let data = try? encode(metadata) else { return }
        try? data.write(to: sidecarURL(for: recording), options: .atomic)
    }

    /// Drops what Apple heard from a recording's sidecar, so the next answer for it isn't checked
    /// against that text again: after one answer was turned down, a check that may be wrong (Apple
    /// listening in another language) must not turn down every retry too.
    static func forgetAppleText(of recording: URL) {
        let sidecar = sidecarURL(for: recording)
        guard let data = try? Data(contentsOf: sidecar), var metadata = decode(data), metadata.appleText != nil else { return }
        metadata.appleText = nil
        writeSidecar(metadata, for: recording)
    }

    /// Records in a recording's sidecar which note its text went to.
    static func setNoteID(_ noteID: PersistentIdentifier, of recording: URL) {
        let sidecar = sidecarURL(for: recording)
        guard let data = try? Data(contentsOf: sidecar), var metadata = decode(data) else { return }
        metadata.noteID = noteID
        writeSidecar(metadata, for: recording)
    }

    /// Deletes a recording and its sidecar.
    static func remove(_ recording: URL) {
        try? FileManager.default.removeItem(at: recording)
        try? FileManager.default.removeItem(at: sidecarURL(for: recording))
    }

    /// Moves a recording into the folder, with a sidecar if `metadata` is given. Returns its new
    /// location, or nil if that failed (the file then stays where it was).
    static func move(
        _ url: URL,
        at date: Date = .now,
        metadata: Metadata? = nil,
        into folder: URL = UnsentRecordings.folder
    ) -> URL? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            var taken = Set((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
            // Every file takes the names of its siblings (same base, any audio extension), so a new
            // recording never shares a sidecar with an old one.
            for item in taken {
                let base = URL(filePath: item).deletingPathExtension().lastPathComponent
                guard isRecording(URL(filePath: item)) || item.hasSuffix(".json") else { continue }
                for ext in audioExtensions { taken.insert("\(base).\(ext)") }
            }
            let ext = url.pathExtension.isEmpty ? "aac" : url.pathExtension
            // Named after when it was recorded, the same time the menu shows.
            let name = fileName(for: metadata?.date ?? date, taken: taken, fileExtension: ext)
            let destination = folder.appending(path: name)
            try manager.moveItem(at: url, to: destination)
            if let metadata { writeSidecar(metadata, for: destination) }
            return destination
        } catch {
            return nil
        }
    }

    /// The recordings in the folder, oldest first. Sidecars and other files are ignored. A recording
    /// whose sidecar is missing or unreadable (one a crash left behind) takes its length from the audio
    /// file and its date from the file's modification date.
    static func list(in folder: URL = UnsentRecordings.folder) -> [Recording] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        // A sidecar whose recording is gone (deleted in Finder) is removed.
        let audioBases = Set(items.filter(isRecording).map { $0.deletingPathExtension().lastPathComponent })
        for item in items where item.pathExtension == "json" && !audioBases.contains(item.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: item)
        }
        return items.filter(isRecording).map { url in
            if let data = try? Data(contentsOf: sidecarURL(for: url)), let metadata = decode(data) {
                return Recording(
                    url: url, date: metadata.date, duration: metadata.duration, noteID: metadata.noteID,
                    appleText: metadata.appleText
                )
            }
            let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .now
            let duration = audioDuration(of: url)
            // Written back, so the slow way of finding the length runs once per file.
            writeSidecar(Metadata(duration: duration, date: date, noteID: nil), for: url)
            return Recording(url: url, date: date, duration: duration, noteID: nil)
        }
        .sorted { ($0.date, $0.url.lastPathComponent) < ($1.date, $1.url.lastPathComponent) }
    }

    /// The length of an audio file in seconds. If it can't be opened, a guess from its size: 24 bit
    /// 16 kHz FLAC is about 36 kB/s and the AAC fallback about 6 kB/s. 0 if the file is empty.
    static func audioDuration(of url: URL) -> TimeInterval {
        if let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0, file.length > 0 {
            return Double(file.length) / file.processingFormat.sampleRate
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return estimatedDuration(bytes: size, fileExtension: url.pathExtension)
    }

    static func estimatedDuration(bytes: Int, fileExtension: String) -> TimeInterval {
        Double(bytes) / (fileExtension == "flac" ? 36_000 : 6_000)
    }

    /// How many recordings are waiting.
    static func count(in folder: URL = UnsentRecordings.folder) -> Int {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return items.filter { isRecording(URL(filePath: $0)) }.count
    }

    /// The menu's label for a recording: `Today 14:03 · 2:15`, `Yesterday 09:30 · 0:42`, or the date
    /// for older ones (with the year if it isn't this year). Lengths of an hour or more show hours.
    static func menuLabel(
        date: Date,
        duration: TimeInterval,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"

        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Today"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM y")
            day = formatter.string(from: date)
        }
        return "\(day) \(time.string(from: date)) · \(lengthText(duration))"
    }

    /// `2:15`, or `1:02:15` from an hour up.
    static func lengthText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
