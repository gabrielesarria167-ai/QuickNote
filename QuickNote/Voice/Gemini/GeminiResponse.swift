import Foundation

/// What Gemini heard, and the title it gave the recording.
struct Transcription: Equatable, Sendable {
    var title: String
    var transcript: String
}

/// Why Gemini didn't give a transcription.
enum GeminiError: Error, Equatable, Sendable {
    /// The API key was rejected.
    case badKey
    /// Too many requests, or the quota is used up.
    case quota
    /// Google's server failed or was too slow.
    case server
    /// Gemini refused to answer (safety or similar).
    case blocked
    /// The answer was cut off at the output limit.
    case truncated
    /// The request or the answer wasn't what was expected.
    case malformed
    /// Nothing was said, or there was no audio.
    case empty
    /// The recording is too big to send in one request.
    case tooLarge
    /// There was no connection to Google.
    case offline
}

/// Turns Gemini's HTTP answer into a `Transcription` or a `GeminiError`.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum GeminiResponse {
    private struct Failure: Decodable {
        struct Body: Decodable {
            struct Detail: Decodable {
                var reason: String?
            }
            var message: String?
            var details: [Detail]?
        }
        var error: Body?
    }

    private struct Success: Decodable {
        struct Feedback: Decodable {
            var blockReason: String?
        }
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    var text: String?
                }
                var parts: [Part]?
            }
            var content: Content?
            var finishReason: String?
        }
        var promptFeedback: Feedback?
        var candidates: [Candidate]?
    }

    private struct Answer: Decodable {
        var title: String?
        var transcript: String?
    }

    private static let blockingFinishReasons: Set<String> = ["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST"]

    static func parse(data: Data, statusCode: Int) -> Result<Transcription, GeminiError> {
        guard (200..<300).contains(statusCode) else {
            return .failure(error(data: data, statusCode: statusCode))
        }
        guard let response = try? JSONDecoder().decode(Success.self, from: data) else {
            return .failure(.malformed)
        }
        if response.promptFeedback?.blockReason != nil {
            return .failure(.blocked)
        }
        guard let candidate = response.candidates?.first else {
            return .failure(.malformed)
        }
        if let reason = candidate.finishReason {
            if blockingFinishReasons.contains(reason) { return .failure(.blocked) }
            if reason == "MAX_TOKENS" { return .failure(.truncated) }
        }

        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.empty)
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: Data(withoutFences(text).utf8)),
              let transcript = answer.transcript
        else { return .failure(.malformed) }

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        return .success(Transcription(
            title: (answer.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            transcript: trimmed
        ))
    }

    private static func error(data: Data, statusCode: Int) -> GeminiError {
        switch statusCode {
        case 400:
            let body = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            let reasons = (body?.details ?? []).compactMap(\.reason) + [body?.message ?? ""]
            let rejected = reasons.contains { $0.localizedCaseInsensitiveContains("API_KEY_INVALID") || $0.localizedCaseInsensitiveContains("API key not valid") }
            return rejected ? .badKey : .malformed
        case 401, 403: return .badKey
        case 413: return .tooLarge
        case 429: return .quota
        case 400..<500 where statusCode != 408: return .malformed
        default: return .server
        }
    }

    /// The text without a Markdown code fence (```json … ```) around it, if the model added one.
    private static func withoutFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.hasPrefix("```") else { return result }
        if let newline = result.firstIndex(of: "\n") {
            result = String(result[result.index(after: newline)...])
        } else {
            result.removeFirst(3)
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix("```") { result.removeLast(3) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
