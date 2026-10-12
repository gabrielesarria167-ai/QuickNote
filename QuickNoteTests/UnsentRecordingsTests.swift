import Foundation
import SwiftData
import Testing
@testable import QuickNote

struct UnsentRecordingsTests {
    private func date(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        DateComponents(calendar: .current, year: 2026, month: 10, day: 10, hour: hour, minute: minute, second: second).date!
    }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "UnsentRecordingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func theFileNameKeepsTheRecordingsExtension() {
        let taken: Set<String> = ["2026-10-10 14.03.22.flac"]
        #expect(UnsentRecordings.fileName(for: date(14, 3, 22), taken: taken, fileExtension: "flac") == "2026-10-10 14.03.22 2.flac")
    }

    @Test func fileNamesAreTheTimeWithoutColons() {
        #expect(UnsentRecordings.fileName(for: date(14, 3, 22)) == "2026-10-10 14.03.22.aac")
        #expect(UnsentRecordings.fileName(for: date(9, 5, 7)) == "2026-10-10 09.05.07.aac")
    }

    @Test func aTakenNameGetsANumber() {
        let taken: Set<String> = ["2026-10-10 14.03.22.aac", "2026-10-10 14.03.22 2.aac"]
        #expect(UnsentRecordings.fileName(for: date(14, 3, 22), taken: taken) == "2026-10-10 14.03.22 3.aac")
        #expect(UnsentRecordings.fileName(for: date(14, 3, 23), taken: taken) == "2026-10-10 14.03.23.aac")
    }

    @Test func aFailedTranscriptionKeepsTheAudio() {
        for error in [GeminiError.badKey, .badModel, .quota, .server, .blocked, .truncated, .malformed, .tooLarge, .offline, .mismatch] {
            #expect(UnsentRecordings.shouldKeep(after: .failure(error)))
        }
    }

    @Test func aSuccessOrANoSpeechAnswerDeletesTheAudio() {
        #expect(!UnsentRecordings.shouldKeep(after: .success(Transcription(title: "T", transcript: "x"))))
        #expect(!UnsentRecordings.shouldKeep(after: .failure(.empty)))
    }

    @Test func aNoSpeechAnswerKeepsTheAudioOfALongOrIncompleteRecording() {
        #expect(UnsentRecordings.shouldKeep(after: .failure(.empty), appleIncomplete: true, duration: 5))
        #expect(UnsentRecordings.shouldKeep(after: .failure(.empty), appleIncomplete: false, duration: 31))
        #expect(!UnsentRecordings.shouldKeep(after: .failure(.empty), appleIncomplete: false, duration: 30))
        #expect(!UnsentRecordings.shouldKeep(after: .success(Transcription(title: "T", transcript: "x")), appleIncomplete: true, duration: 600))
    }

    @Test func aFileInTheFolderIsRecognized() {
        let folder = tempFolder()
        #expect(UnsentRecordings.contains(folder.appending(path: "a.aac"), in: folder))
        #expect(!UnsentRecordings.contains(folder.deletingLastPathComponent().appending(path: "a.aac"), in: folder))
        #expect(!UnsentRecordings.contains(folder.appending(path: "sub").appending(path: "a.aac"), in: folder))
    }

    @Test func stoppingTheWaitKeepsTheAudioOnlyWhenAppleHeardLessThanAll() {
        #expect(UnsentRecordings.shouldKeepWhenStoppedWaiting(appleIncomplete: true))
        #expect(!UnsentRecordings.shouldKeepWhenStoppedWaiting(appleIncomplete: false))
    }

    @Test func movingAFileKeepsItsContentsUnderADatedName() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString).aac")
        try Data([1, 2, 3]).write(to: source)

        let moved = try #require(UnsentRecordings.move(source, at: date(14, 3, 22), into: folder))
        #expect(moved.lastPathComponent == "2026-10-10 14.03.22.aac")
        #expect(try Data(contentsOf: moved) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(UnsentRecordings.count(in: folder) == 1)
    }

    @Test func twoMovesInTheSameSecondDoNotOverwrite() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        for byte in 1...2 {
            let source = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString).aac")
            try Data([UInt8(byte)]).write(to: source)
            #expect(UnsentRecordings.move(source, at: date(14, 3, 22), into: folder) != nil)
        }
        #expect(UnsentRecordings.count(in: folder) == 2)
    }

    @Test func movingAMissingFileFails() {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).aac")
        #expect(UnsentRecordings.move(missing, into: folder) == nil)
    }

    @Test func countingAnAbsentFolderGivesZero() {
        #expect(UnsentRecordings.count(in: tempFolder()) == 0)
    }

    // MARK: Sidecars

    private func write(_ name: String, in folder: URL, bytes: Int = 4) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    @Test func aSidecarSitsNextToTheRecordingWithTheSameBaseName() {
        let url = URL(filePath: "/x/2026-10-10 14.03.22.flac")
        #expect(UnsentRecordings.sidecarURL(for: url).path == "/x/2026-10-10 14.03.22.json")
    }

    @Test @MainActor func aSidecarSurvivesEncodingAndDecoding() throws {
        let container = try ModelContainer(for: Note.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let note = Note(text: "hi")
        container.mainContext.insert(note)
        try container.mainContext.save()

        let metadata = UnsentRecordings.Metadata(duration: 135.5, date: Date(timeIntervalSince1970: 1_700_000_000), noteID: note.persistentModelID)
        let decoded = try #require(UnsentRecordings.decode(try UnsentRecordings.encode(metadata)))
        #expect(decoded == metadata)

        let noNote = UnsentRecordings.Metadata(duration: 3, date: Date(timeIntervalSince1970: 1_700_000_000), noteID: nil)
        #expect(UnsentRecordings.decode(try UnsentRecordings.encode(noNote)) == noNote)

        var heard = noNote
        heard.appleText = "what Apple heard"
        #expect(UnsentRecordings.decode(try UnsentRecordings.encode(heard)) == heard)
    }

    @Test func aSidecarWrittenBeforeAppleTextWasKeptStillDecodes() throws {
        let old = Data(#"{"duration":3,"date":"2023-11-14T22:13:20Z"}"#.utf8)
        let decoded = try #require(UnsentRecordings.decode(old))
        #expect(decoded.duration == 3)
        #expect(decoded.appleText == nil)
    }

    @Test func garbageIsNotASidecar() {
        #expect(UnsentRecordings.decode(Data("nope".utf8)) == nil)
        #expect(UnsentRecordings.decode(Data()) == nil)
    }

    @Test func movingWithMetadataWritesTheSidecar() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString).flac")
        try Data([1]).write(to: source)
        let metadata = UnsentRecordings.Metadata(duration: 12, date: date(14, 3, 22), noteID: nil)

        let moved = try #require(UnsentRecordings.move(source, at: date(14, 3, 22), metadata: metadata, into: folder))
        let data = try Data(contentsOf: UnsentRecordings.sidecarURL(for: moved))
        #expect(UnsentRecordings.decode(data) == metadata)
        #expect(UnsentRecordings.count(in: folder) == 1)
    }

    @Test func aNewRecordingNeverTakesOverALeftoverSidecarsName() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try write("2026-10-10 14.03.22.json", in: folder)
        let source = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString).flac")
        try Data([1]).write(to: source)

        let moved = try #require(UnsentRecordings.move(source, at: date(14, 3, 22), into: folder))
        #expect(moved.lastPathComponent == "2026-10-10 14.03.22 2.flac")
    }

    @Test func removingARecordingRemovesItsSidecarToo() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = try write("a.flac", in: folder)
        let other = try write("b.flac", in: folder)
        let sidecar = try write("a.json", in: folder)
        let otherSidecar = try write("b.json", in: folder)

        UnsentRecordings.remove(audio)
        #expect(!FileManager.default.fileExists(atPath: audio.path))
        #expect(!FileManager.default.fileExists(atPath: sidecar.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(FileManager.default.fileExists(atPath: otherSidecar.path))
        UnsentRecordings.remove(audio)
    }

    @Test func theListIsOldestFirstAndIgnoresSidecarsAndStrayFiles() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let newer = try write("newer.flac", in: folder)
        let older = try write("older.aac", in: folder)
        _ = try write("notes.txt", in: folder)
        _ = try write(".DS_Store", in: folder)
        UnsentRecordings.writeSidecar(.init(duration: 10, date: date(15, 0, 0), noteID: nil), for: newer)
        UnsentRecordings.writeSidecar(.init(duration: 20, date: date(9, 0, 0), noteID: nil), for: older)

        let list = UnsentRecordings.list(in: folder)
        #expect(list.map(\.url.lastPathComponent) == ["older.aac", "newer.flac"])
        #expect(list.map(\.duration) == [20, 10])
        #expect(list.count == UnsentRecordings.count(in: folder))
    }

    @Test func aMissingOrBrokenSidecarFallsBackToTheFile() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let plain = try write("plain.aac", in: folder)
        let broken = try write("broken.aac", in: folder)
        try Data("{".utf8).write(to: UnsentRecordings.sidecarURL(for: broken))
        let modified = date(8, 30, 0)
        for url in [plain, broken] {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }

        let list = UnsentRecordings.list(in: folder)
        #expect(list.count == 2)
        for recording in list {
            #expect(recording.date == modified)
            #expect(recording.duration == UnsentRecordings.estimatedDuration(bytes: 4, fileExtension: "aac"))
            #expect(recording.noteID == nil)
        }
    }

    @Test func listingAnAbsentFolderGivesNothing() {
        #expect(UnsentRecordings.list(in: tempFolder()).isEmpty)
    }

    // MARK: Menu labels

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        DateComponents(calendar: utc, timeZone: utc.timeZone, year: year, month: month, day: day, hour: hour, minute: minute).date!
    }

    private func label(_ date: Date, _ duration: TimeInterval) -> String {
        UnsentRecordings.menuLabel(
            date: date, duration: duration, now: utcDate(2026, 10, 10, 18, 0),
            calendar: utc, locale: Locale(identifier: "en_GB")
        )
    }

    @Test func todaysRecordingsSayToday() {
        #expect(label(utcDate(2026, 10, 10, 14, 3), 135) == "Today 14:03 · 2:15")
    }

    @Test func yesterdaysRecordingsSayYesterday() {
        #expect(label(utcDate(2026, 10, 9, 9, 5), 42) == "Yesterday 09:05 · 0:42")
    }

    @Test func olderRecordingsShowTheDate() {
        #expect(label(utcDate(2026, 10, 1, 23, 59), 60) == "1 Oct 23:59 · 1:00")
        #expect(label(utcDate(2025, 12, 31, 8, 0), 60) == "31 Dec 2025 08:00 · 1:00")
    }

    @Test func lengthsShowHoursFromAnHourUp() {
        #expect(UnsentRecordings.lengthText(0) == "0:00")
        #expect(UnsentRecordings.lengthText(59.6) == "1:00")
        #expect(UnsentRecordings.lengthText(3725) == "1:02:05")
        #expect(UnsentRecordings.lengthText(-4) == "0:00")
    }

    @Test func aSizeEstimateStandsInForAnUnreadableFile() {
        #expect(UnsentRecordings.estimatedDuration(bytes: 360_000, fileExtension: "flac") == 10)
        #expect(UnsentRecordings.estimatedDuration(bytes: 60_000, fileExtension: "aac") == 10)
        #expect(UnsentRecordings.estimatedDuration(bytes: 0, fileExtension: "flac") == 0)
    }

    @Test func listingWritesTheFallbackBackAsASidecar() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try write("a.flac", in: folder, bytes: 72_000)
        _ = UnsentRecordings.list(in: folder)
        let stored = try #require(UnsentRecordings.decode(try Data(contentsOf: UnsentRecordings.sidecarURL(for: url))))
        #expect(stored.duration == 2)
    }

    @Test func listingRemovesSidecarsWithoutARecording() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let orphan = try write("gone.json", in: folder)
        _ = try write("here.aac", in: folder)
        _ = UnsentRecordings.list(in: folder)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func aRecordingWithADifferentExtensionDoesNotShareASidecar() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try write("2026-10-10 14.03.22.aac", in: folder)
        let source = FileManager.default.temporaryDirectory.appending(path: "move-\(UUID().uuidString).flac")
        try Data([1]).write(to: source)
        let moved = try #require(UnsentRecordings.move(source, at: date(14, 3, 22), into: folder))
        #expect(moved.lastPathComponent == "2026-10-10 14.03.22 2.flac")
    }

    @Test @MainActor func aSavedNotesIDResolvesInAnotherContext() throws {
        let container = try ModelContainer(for: Note.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let note = Note(text: "hi")
        container.mainContext.insert(note)
        try container.mainContext.save()
        let data = try UnsentRecordings.encode(.init(duration: 1, date: .now, noteID: note.persistentModelID))
        let id = try #require(UnsentRecordings.decode(data)?.noteID)
        let found = try ModelContext(container).fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.persistentModelID == id }))
        #expect(found.count == 1)
        #expect(found.first?.text == "hi")
    }
}
