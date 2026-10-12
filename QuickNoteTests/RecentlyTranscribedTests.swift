import Foundation
import Testing
@testable import QuickNote

struct RecentlyTranscribedTests {
    private let made = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "RecentlyTranscribedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func recording(in folder: URL, name: String = "rec.flac") throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    private func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    @Test func aTranscribedRecordingIsMovedWithItsSidecarAndDatedNow() throws {
        let source = tempFolder(), folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: folder) }
        let url = try recording(in: source)
        let metadata = UnsentRecordings.Metadata(duration: 600, date: made, noteID: nil, appleText: "hola")
        let now = made.addingTimeInterval(700)

        let moved = try #require(RecentlyTranscribed.keep(url, metadata: metadata, now: now, in: folder))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(UnsentRecordings.contains(moved, in: folder))
        #expect(modified(moved) == now)
        #expect(UnsentRecordings.list(in: folder).map(\.date) == [made])
    }

    @Test func aRetriedRecordingBringsTheSidecarItAlreadyHas() throws {
        let unsent = tempFolder(), folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: unsent); try? FileManager.default.removeItem(at: folder) }
        let url = try recording(in: unsent)
        UnsentRecordings.writeSidecar(UnsentRecordings.Metadata(duration: 42, date: made, noteID: nil), for: url)

        let moved = try #require(RecentlyTranscribed.keep(url, in: folder))
        #expect(!FileManager.default.fileExists(atPath: UnsentRecordings.sidecarURL(for: url).path))
        #expect(UnsentRecordings.list(in: folder).first?.duration == 42)
        #expect(UnsentRecordings.list(in: folder).first?.url.lastPathComponent == moved.lastPathComponent)
    }

    @Test func transcribingAgainOnlyRestartsTheWeek() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try recording(in: folder)
        let now = made.addingTimeInterval(3 * 86_400)

        #expect(RecentlyTranscribed.keep(url, now: now, in: folder) == url)
        #expect(modified(url) == now)
        #expect(UnsentRecordings.list(in: folder).count == 1)
    }

    @Test func onlyRecordingsOlderThanAWeekArePurged() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = try recording(in: folder, name: "old.flac")
        let recent = try recording(in: folder, name: "recent.flac")
        UnsentRecordings.writeSidecar(UnsentRecordings.Metadata(duration: 1, date: made, noteID: nil), for: old)
        let now = made.addingTimeInterval(30 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-RecentlyTranscribed.keepFor - 60)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-RecentlyTranscribed.keepFor + 60)], ofItemAtPath: recent.path)

        RecentlyTranscribed.purge(now: now, in: folder)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(!FileManager.default.fileExists(atPath: UnsentRecordings.sidecarURL(for: old).path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
    }

    @Test func forgettingAppleTextKeepsTheRestOfTheSidecar() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try recording(in: folder)
        UnsentRecordings.writeSidecar(UnsentRecordings.Metadata(duration: 9, date: made, noteID: nil, appleText: "hola"), for: url)

        UnsentRecordings.forgetAppleText(of: url)
        let data = try Data(contentsOf: UnsentRecordings.sidecarURL(for: url))
        #expect(UnsentRecordings.decode(data) == UnsentRecordings.Metadata(duration: 9, date: made, noteID: nil))
    }

    @Test func theRecordingBeingTranscribedAgainIsNotPurged() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try recording(in: folder)
        let now = made.addingTimeInterval(30 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: made], ofItemAtPath: url.path)

        RecentlyTranscribed.purge(now: now, sparing: url, in: folder)
        #expect(FileManager.default.fileExists(atPath: url.path))
        RecentlyTranscribed.purge(now: now, in: folder)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
