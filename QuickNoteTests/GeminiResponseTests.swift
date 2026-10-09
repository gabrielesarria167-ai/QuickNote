import Foundation
import Testing
@testable import QuickNote

struct GeminiResponseTests {
    private func parse(_ json: String, status: Int = 200) -> Result<Transcription, GeminiError> {
        GeminiResponse.parse(data: Data(json.utf8), statusCode: status)
    }

    /// A success answer whose text is `text` (JSON-escaped here).
    private func answer(_ text: String, finishReason: String = "STOP") -> String {
        let escaped = String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        return #"{"candidates":[{"content":{"role":"model","parts":[{"text":\#(escaped)}]},"finishReason":"\#(finishReason)"}]}"#
    }

    @Test func aGoodAnswerGivesTheTitleAndTranscript() {
        let result = parse(answer(#"{"title":"Trip plan","transcript":"Buy tickets."}"#))
        #expect(result == .success(Transcription(title: "Trip plan", transcript: "Buy tickets.")))
    }

    @Test func titleAndTranscriptAreTrimmed() {
        let result = parse(answer(#"{"title":"  Trip plan\n","transcript":"\n Buy tickets. \n"}"#))
        #expect(result == .success(Transcription(title: "Trip plan", transcript: "Buy tickets.")))
    }

    @Test func textSplitOverSeveralPartsIsJoined() {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"{\"title\":\"A\","},{"text":"\"transcript\":\"B\"}"}]},"finishReason":"STOP"}]}"#
        #expect(parse(json) == .success(Transcription(title: "A", transcript: "B")))
    }

    @Test func textInACodeFenceIsAccepted() {
        let fenced = "```json\n{\"title\":\"A\",\"transcript\":\"B\"}\n```"
        #expect(parse(answer(fenced)) == .success(Transcription(title: "A", transcript: "B")))
        let bare = "```\n{\"title\":\"A\",\"transcript\":\"B\"}```"
        #expect(parse(answer(bare)) == .success(Transcription(title: "A", transcript: "B")))
    }

    @Test func nonLatinTextSurvives() {
        let result = parse(answer(#"{"title":"旅行の計画","transcript":"Voglio comprare i biglietti. チケットを買います。"}"#))
        #expect(result == .success(Transcription(title: "旅行の計画", transcript: "Voglio comprare i biglietti. チケットを買います。")))
    }

    @Test func aMissingTitleGivesAnEmptyOne() {
        #expect(parse(answer(#"{"transcript":"Hello"}"#)) == .success(Transcription(title: "", transcript: "Hello")))
    }

    @Test func anEmptyTranscriptIsEmpty() {
        #expect(parse(answer(#"{"title":"","transcript":""}"#)) == .failure(.empty))
        #expect(parse(answer(#"{"title":"x","transcript":"  \n"}"#)) == .failure(.empty))
    }

    @Test func noTextAtAllIsEmpty() {
        #expect(parse(#"{"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}"#) == .failure(.empty))
        #expect(parse(#"{"candidates":[{"finishReason":"STOP"}]}"#) == .failure(.empty))
    }

    @Test func aMissingTranscriptOrBrokenJSONIsMalformed() {
        #expect(parse(answer(#"{"title":"x"}"#)) == .failure(.malformed))
        #expect(parse(answer("Sure! Here is the transcript.")) == .failure(.malformed))
        #expect(parse(answer(#"{"title":"x","transcript":"cut o"#)) == .failure(.malformed))
        #expect(parse("not json") == .failure(.malformed))
        #expect(parse("{}") == .failure(.malformed))
        #expect(parse(#"{"candidates":[]}"#) == .failure(.malformed))
    }

    @Test func aBlockedPromptIsBlocked() {
        #expect(parse(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#) == .failure(.blocked))
        #expect(parse(#"{"promptFeedback":{"blockReason":"OTHER"},"candidates":[]}"#) == .failure(.blocked))
    }

    @Test func aSafetyStopIsBlocked() {
        for reason in ["SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST"] {
            #expect(parse(answer("", finishReason: reason)) == .failure(.blocked))
        }
    }

    @Test func hittingTheOutputLimitIsTruncated() {
        #expect(parse(answer(#"{"title":"x","transcript":"half a sen"#, finishReason: "MAX_TOKENS")) == .failure(.truncated))
    }

    @Test func aRejectedKeyIs400WithTheReasonOr401Or403() {
        let byReason = #"{"error":{"code":400,"message":"Bad.","status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"API_KEY_INVALID","domain":"googleapis.com"}]}}"#
        #expect(parse(byReason, status: 400) == .failure(.badKey))
        let byMessage = #"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#
        #expect(parse(byMessage, status: 400) == .failure(.badKey))
        #expect(parse(#"{"error":{"code":401}}"#, status: 401) == .failure(.badKey))
        #expect(parse(#"{"error":{"code":403,"status":"PERMISSION_DENIED"}}"#, status: 403) == .failure(.badKey))
    }

    @Test func otherBadRequestsAreMalformed() {
        let json = #"{"error":{"code":400,"message":"Invalid value at 'contents'.","status":"INVALID_ARGUMENT"}}"#
        #expect(parse(json, status: 400) == .failure(.malformed))
        #expect(parse("", status: 400) == .failure(.malformed))
        #expect(parse(#"{"error":{"code":404,"message":"models/x is not found"}}"#, status: 404) == .failure(.malformed))
    }

    @Test func tooManyRequestsIsQuota() {
        #expect(parse(#"{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}"#, status: 429) == .failure(.quota))
    }

    @Test func serverErrorsAndTimeoutsAreServer() {
        #expect(parse(#"{"error":{"code":503,"status":"UNAVAILABLE"}}"#, status: 503) == .failure(.server))
        #expect(parse("", status: 500) == .failure(.server))
        #expect(parse("", status: 504) == .failure(.server))
        #expect(parse("", status: 408) == .failure(.server))
    }

    @Test func aTooBigRequestIsTooLarge() {
        #expect(parse("", status: 413) == .failure(.tooLarge))
    }
}
