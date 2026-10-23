import Foundation
import Testing
@testable import QuickNote

struct GeminiTranscriberTests {
    /// A transport that answers from a script and remembers the requests it got. No network.
    private final class FakeTransport: @unchecked Sendable {
        enum Reply {
            case answer(status: Int, body: String)
            case failure(URLError.Code)
        }

        private let lock = NSLock()
        private var replies: [Reply]
        private var received: [URLRequest] = []

        init(_ replies: [Reply]) {
            self.replies = replies
        }

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return received
        }

        var transport: GeminiTranscriber.Transport {
            { [self] request in
                let reply = next(request)
                switch reply {
                case .answer(let status, let body):
                    let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                    return (Data(body.utf8), response)
                case .failure(let code):
                    throw URLError(code)
                }
            }
        }

        private func next(_ request: URLRequest) -> Reply {
            lock.lock()
            defer { lock.unlock() }
            received.append(request)
            return replies.count > 1 ? replies.removeFirst() : replies[0]
        }
    }

    private static let good = Reply.answer(status: 200, body: #"{"candidates":[{"content":{"parts":[{"text":"{\"title\":\"Trip plan\",\"transcript\":\"Buy tickets.\"}"}]},"finishReason":"STOP"}]}"#)
    private typealias Reply = FakeTransport.Reply

    private func transcribe(_ fake: FakeTransport, bytes: Int = 1000) async throws -> Transcription {
        let url = FileManager.default.temporaryDirectory.appending(path: "GeminiTranscriberTests-\(UUID().uuidString).aac")
        try Data(repeating: 7, count: bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transcriber = GeminiTranscriber(transport: fake.transport, retryDelay: .zero)
        return try await transcriber.transcribe(audioURL: url, duration: 12, apiKey: "SECRET-KEY", model: "gemini-3.8-flash")
    }

    private func failure(_ fake: FakeTransport, bytes: Int = 1000) async -> GeminiError? {
        do {
            _ = try await transcribe(fake, bytes: bytes)
            return nil
        } catch {
            return error as? GeminiError
        }
    }

    @Test func successGivesTheTranscription() async throws {
        let fake = FakeTransport([Self.good])
        let result = try await transcribe(fake)
        #expect(result == Transcription(title: "Trip plan", transcript: "Buy tickets."))
        #expect(fake.requests.count == 1)
    }

    @Test func theRequestCarriesTheKeyInTheHeaderAndTheAudioInTheBody() async throws {
        let fake = FakeTransport([Self.good])
        _ = try await transcribe(fake, bytes: 300)
        let request = try #require(fake.requests.first)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "SECRET-KEY")
        #expect(request.url?.absoluteString.contains("SECRET-KEY") == false)
        #expect(request.url?.path.hasSuffix("/models/gemini-3.8-flash:generateContent") == true)
        #expect(request.timeoutInterval == 72)
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(Data(repeating: 7, count: 300).base64EncodedString()))
        #expect(text.contains("audio/aac"))
        #expect(!text.contains("SECRET-KEY"))
    }

    @Test func aQuotaErrorIsRetriedOnceAndCanSucceed() async throws {
        let fake = FakeTransport([.answer(status: 429, body: "{}"), Self.good])
        let result = try await transcribe(fake)
        #expect(result.transcript == "Buy tickets.")
        #expect(fake.requests.count == 2)
    }

    @Test func aServerErrorIsRetriedOnceThenTriedOnTheFallbackModel() async {
        let fake = FakeTransport([.answer(status: 503, body: "{}")])
        #expect(await failure(fake) == .server)
        #expect(fake.requests.count == 3)
        #expect(fake.requests[1].url?.path.contains("gemini-3.8-flash") == true)
        #expect(fake.requests[2].url?.path.contains(GeminiTranscriber.fallbackModel) == true)
    }

    @Test func theFallbackModelCanSaveTheRecording() async throws {
        let fake = FakeTransport([.answer(status: 503, body: "{}"), .answer(status: 503, body: "{}"), Self.good])
        let result = try await transcribe(fake)
        #expect(result.transcript == "Buy tickets.")
    }

    @Test func theFallbackModelIsNotTriedAgainWhenItIsTheChosenOne() async throws {
        let fake = FakeTransport([.answer(status: 503, body: "{}")])
        let url = FileManager.default.temporaryDirectory.appending(path: "GeminiTranscriberTests-\(UUID().uuidString).aac")
        try Data(repeating: 7, count: 1000).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let transcriber = GeminiTranscriber(transport: fake.transport, retryDelay: .zero)
        await #expect(throws: GeminiError.server) {
            try await transcriber.transcribe(audioURL: url, duration: 12, apiKey: "k", model: GeminiTranscriber.fallbackModel)
        }
        #expect(fake.requests.count == 2)
    }

    @Test func aBadKeyIsNotRetried() async {
        let fake = FakeTransport([.answer(status: 403, body: "{}"), Self.good])
        #expect(await failure(fake) == .badKey)
        #expect(fake.requests.count == 1)
    }

    @Test func anEmptyTranscriptIsNotRetried() async {
        let body = #"{"candidates":[{"content":{"parts":[{"text":"{\"title\":\"\",\"transcript\":\"\"}"}]},"finishReason":"STOP"}]}"#
        let fake = FakeTransport([.answer(status: 200, body: body), Self.good])
        #expect(await failure(fake) == .empty)
        #expect(fake.requests.count == 1)
    }

    @Test func aRecordingTooBigForOneRequestNeverReachesTheNetwork() async {
        let fake = FakeTransport([Self.good])
        #expect(await failure(fake, bytes: 15_000_000) == .tooLarge)
        #expect(fake.requests.isEmpty)
    }

    @Test func aMissingOrEmptyFileIsEmptyWithoutTheNetwork() async throws {
        let fake = FakeTransport([Self.good])
        #expect(await failure(fake, bytes: 0) == .empty)
        let missing = FileManager.default.temporaryDirectory.appending(path: "nope-\(UUID().uuidString).aac")
        let transcriber = GeminiTranscriber(transport: fake.transport, retryDelay: .zero)
        await #expect(throws: GeminiError.empty) {
            try await transcriber.transcribe(audioURL: missing, duration: 5, apiKey: "k", model: "m")
        }
        #expect(fake.requests.isEmpty)
    }

    @Test func noConnectionIsOfflineAndNotRetried() async {
        for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost, .cannotFindHost] {
            let fake = FakeTransport([.failure(code)])
            #expect(await failure(fake) == .offline)
            #expect(fake.requests.count == 1)
        }
    }

    @Test func aTimeoutIsNotRetriedButFallsBackToTheOtherModel() async throws {
        let fake = FakeTransport([.failure(.timedOut), Self.good])
        let result = try await transcribe(fake)
        #expect(result.transcript == "Buy tickets.")
        #expect(fake.requests.count == 2)
        #expect(fake.requests[1].url?.path.contains(GeminiTranscriber.fallbackModel) == true)
    }

    @Test func aCancelledRequestThrowsCancellation() async throws {
        let fake = FakeTransport([.failure(.cancelled)])
        await #expect(throws: CancellationError.self) {
            _ = try await transcribe(fake)
        }
    }
}
