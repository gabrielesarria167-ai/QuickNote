import AppKit
import Foundation
import Testing
@testable import QuickNote

struct AttachmentsTests {
    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AttachmentsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func makeFile(named name: String, contents: String = "hello") throws -> URL {
        let folder = tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func pngData() -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    private func pasteboard(_ fill: (NSPasteboard) -> Void) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("AttachmentsTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        fill(pasteboard)
        return pasteboard
    }

    @Test func addingCopiesTheFileAndKeepsItsName() throws {
        let folder = tempFolder()
        let file = try makeFile(named: "spec.pdf", contents: "pdf")
        let names = Attachments.add([file], in: folder)

        #expect(names.count == 1)
        #expect(Attachments.displayName(names[0]) == "spec.pdf")
        #expect(try String(contentsOf: Attachments.url(for: names[0], in: folder), encoding: .utf8) == "pdf")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func twoFilesWithTheSameNameDontClash() throws {
        let folder = tempFolder()
        let first = try makeFile(named: "photo.png", contents: "one")
        let second = try makeFile(named: "photo.png", contents: "two")
        let names = Attachments.add([first, second], in: folder)

        #expect(names.count == 2)
        #expect(names[0] != names[1])
        #expect(try String(contentsOf: Attachments.url(for: names[1], in: folder), encoding: .utf8) == "two")
    }

    @Test func aMissingFileIsLeftOut() {
        let folder = tempFolder()
        let names = Attachments.add([tempFolder().appending(path: "gone.txt")], in: folder)

        #expect(names.isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty)
    }

    @Test func aFileOnThePasteboardIsAttached() throws {
        let folder = tempFolder()
        let file = try makeFile(named: "notes.txt")
        let names = Attachments.add(from: pasteboard { $0.writeObjects([file as NSURL]) }, in: folder)

        #expect(names.map(Attachments.displayName) == ["notes.txt"])
    }

    @Test func aPastedImageIsSavedAsPNG() throws {
        let folder = tempFolder()
        let date = DateComponents(calendar: .current, year: 2026, month: 10, day: 16, hour: 9, minute: 5, second: 7).date!
        let names = Attachments.add(from: pasteboard { $0.setData(pngData(), forType: .png) }, in: folder, now: date)

        #expect(names.map(Attachments.displayName) == ["Pasted Image 2026-10-16 09.05.07.png"])
        let data = try Data(contentsOf: Attachments.url(for: names[0], in: folder))
        #expect(NSBitmapImageRep(data: data) != nil)
    }

    @Test func textIsLeftForTheEditor() {
        let folder = tempFolder()
        #expect(Attachments.add(from: pasteboard { $0.setString("hi", forType: .string) }, in: folder).isEmpty)
        let textWithImage = pasteboard {
            $0.declareTypes([.string, .png], owner: nil)
            $0.setString("caption", forType: .string)
            $0.setData(pngData(), forType: .png)
        }
        #expect(Attachments.add(from: textWithImage, in: folder).isEmpty)
    }

    @Test func orphansAreRemovedAndReferencedFilesKept() throws {
        let folder = tempFolder()
        let kept = Attachments.add([try makeFile(named: "keep.txt")], in: folder)
        let dropped = Attachments.add([try makeFile(named: "drop.txt")], in: folder)

        Attachments.removeOrphans(keeping: kept, in: folder)

        #expect(FileManager.default.fileExists(atPath: Attachments.url(for: kept[0], in: folder).path))
        #expect(!FileManager.default.fileExists(atPath: Attachments.url(for: dropped[0], in: folder).deletingLastPathComponent().path))
    }

    @Test func aNoteWithOnlyAnAttachmentIsNotBlank() {
        #expect(Note().isBlank)
        let note = Note(attachments: ["ABC/photo.png"])
        #expect(!note.isBlank)
        #expect(note.title == "photo.png")
    }
}
