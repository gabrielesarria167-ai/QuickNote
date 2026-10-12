import Foundation

/// Recordings Gemini transcribed, kept for a week in `Application Support/<bundle id>/Recently
/// Transcribed` before they are deleted. Gemini sometimes answers with text it made up, and nothing
/// can always tell (not when Apple's recognizer listened in another language), so the audio stays
/// long enough to notice and transcribe it again.
enum RecentlyTranscribed {
    static var folder: URL {
        UnsentRecordings.folder.deletingLastPathComponent()
            .appending(path: "Recently Transcribed", directoryHint: .isDirectory)
    }

    /// How long a recording stays after it was transcribed.
    static let keepFor: TimeInterval = 7 * 24 * 60 * 60

    /// Moves a transcribed recording into `folder` and dates it `now`, which starts its week. Its
    /// sidecar comes along: `metadata` if given, otherwise the one next to it (a retried recording
    /// already has one). A recording already in the folder only gets its week restarted. Returns the
    /// new location, or nil if the move failed (the file then stays where it was).
    @discardableResult
    static func keep(
        _ url: URL,
        metadata: UnsentRecordings.Metadata? = nil,
        now: Date = .now,
        in folder: URL = RecentlyTranscribed.folder
    ) -> URL? {
        if UnsentRecordings.contains(url, in: folder) {
            touch(url, at: now)
            return url
        }
        let oldSidecar = UnsentRecordings.sidecarURL(for: url)
        let existing = (try? Data(contentsOf: oldSidecar)).flatMap(UnsentRecordings.decode)
        guard let moved = UnsentRecordings.move(url, at: now, metadata: metadata ?? existing, into: folder) else {
            return nil
        }
        try? FileManager.default.removeItem(at: oldSidecar)
        touch(moved, at: now)
        return moved
    }

    /// Deletes the recordings (and their sidecars) that were transcribed more than `keepFor` ago,
    /// except `sparing`.
    static func purge(now: Date = .now, sparing: URL? = nil, in folder: URL = RecentlyTranscribed.folder) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        for url in items where UnsentRecordings.isRecording(url) && url.lastPathComponent != sparing?.lastPathComponent {
            guard let date = (try? url.resourceValues(forKeys: keys))?.contentModificationDate,
                  now.timeIntervalSince(date) > keepFor
            else { continue }
            UnsentRecordings.remove(url)
        }
    }

    /// The modification date is when the recording was transcribed; the sidecar keeps when it was made.
    private static func touch(_ url: URL, at date: Date) {
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
