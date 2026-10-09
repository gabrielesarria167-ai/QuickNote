import Foundation
import Testing
@testable import QuickNote

struct UnsentRecordingsTests {
    private func date(_ hour: Int, _ minute: Int, _ second: Int) -> Date {
        DateComponents(calendar: .current, year: 2026, month: 10, day: 10, hour: hour, minute: minute, second: second).date!
    }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "UnsentRecordingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        for error in [GeminiError.badKey, .badModel, .quota, .server, .blocked, .truncated, .malformed, .tooLarge, .offline] {
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
}
