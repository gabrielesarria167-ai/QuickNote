import Foundation
import Testing
@testable import QuickNote

struct GeminiRequestTests {
    private func json(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeBody(audio: Data = Data([1, 2, 3, 250, 251, 252])) throws -> Data {
        try GeminiRequest.body(audio: audio, mimeType: "audio/aac", prompt: "Say it.", maxOutputTokens: 2000)
    }

    @Test func bodyHasOneUserContentWithTheTextThenTheAudio() throws {
        let body = try json(makeBody())
        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.count == 1)
        #expect(contents[0]["role"] as? String == "user")
        let parts = try #require(contents[0]["parts"] as? [[String: Any]])
        #expect(parts.count == 2)
        #expect(parts[0]["text"] as? String == "Say it.")
        #expect(parts[0]["inlineData"] == nil)
        let inline = try #require(parts[1]["inlineData"] as? [String: Any])
        #expect(parts[1]["text"] == nil)
        #expect(inline["mimeType"] as? String == "audio/aac")
    }

    @Test func audioIsBase64() throws {
        let audio = Data([1, 2, 3, 250, 251, 252, 253])
        let body = try json(makeBody(audio: audio))
        let parts = try #require((body["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        let inline = try #require(parts[1]["inlineData"] as? [String: Any])
        #expect(inline["data"] as? String == audio.base64EncodedString())
    }

    @Test func generationConfigAsksForJSONWithTheTitleAndTranscript() throws {
        let body = try json(makeBody())
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["temperature"] == nil)
        #expect(config["maxOutputTokens"] as? Int == 2000)
        #expect(config["thinkingConfig"] == nil)

        let schema = try #require(config["responseSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "OBJECT")
        #expect(schema["required"] as? [String] == ["title", "transcript"])
        #expect(schema["propertyOrdering"] as? [String] == ["transcript", "title"])
        let properties = try #require(schema["properties"] as? [String: [String: String]])
        #expect(properties["title"] == ["type": "STRING"])
        #expect(properties["transcript"] == ["type": "STRING"])
    }

    @Test func thinkingIsTurnedDownOnlyForModelsKnownToAcceptIt() throws {
        #expect(GeminiRequest.thinkingConfig(forModel: "gemini-3.8-flash")?.thinkingLevel == "low")
        #expect(GeminiRequest.thinkingConfig(forModel: " models/Gemini-3.5-flash-lite ")?.thinkingLevel == "low")
        #expect(GeminiRequest.thinkingConfig(forModel: "gemini-2.5-flash")?.thinkingBudget == 0)
        #expect(GeminiRequest.thinkingConfig(forModel: "gemini-2.5-flash")?.thinkingLevel == nil)
        #expect(GeminiRequest.thinkingConfig(forModel: "gemini-2.5-pro") == nil)
        #expect(GeminiRequest.thinkingConfig(forModel: "my-tuned-model") == nil)

        let body = try GeminiRequest.body(audio: Data([1]), mimeType: "audio/aac", prompt: "x", maxOutputTokens: 100, model: "gemini-3.8-flash")
        let config = try #require(json(body)["generationConfig"] as? [String: Any])
        #expect(config["thinkingConfig"] as? [String: String] == ["thinkingLevel": "low"])
    }

    @Test func promptAsksForEveryWord() {
        let prompt = GeminiRequest.prompt
        #expect(prompt.contains("every word"))
        #expect(prompt.contains("Never summarize"))
    }

    @Test func promptSaysNotToTranslateAndToTitleTheNote() {
        let prompt = GeminiRequest.prompt
        #expect(prompt.contains("Never translate"))
        #expect(prompt.contains("title"))
        #expect(prompt.contains("empty transcript"))
    }

    @Test func requestIsAPostWithTheKeyOnlyInTheHeader() throws {
        let body = try makeBody()
        let request = GeminiRequest.urlRequest(model: "gemini-3.8-flash", apiKey: "SECRET-KEY", body: body, timeout: 90)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "SECRET-KEY")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 90)
        #expect(request.httpBody == body)
        #expect(request.url?.absoluteString.contains("SECRET-KEY") == false)
        #expect(String(decoding: body, as: UTF8.self).contains("SECRET-KEY") == false)
    }

    @Test func aModelsPrefixAndWhitespaceAreStripped() {
        #expect(GeminiRequest.normalizedModel("models/gemini-3.8-flash") == "gemini-3.8-flash")
        #expect(GeminiRequest.normalizedModel("  gemini-3.8-flash \n") == "gemini-3.8-flash")
        #expect(GeminiRequest.normalizedModel(" models/x ") == "x")
        #expect(GeminiRequest.normalizedModel("tunedModels/x") == "tunedModels/x")
        let request = GeminiRequest.urlRequest(model: "models/gemini-3.8-flash", apiKey: "k", body: Data(), timeout: 60)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent")
    }

    @Test func modelIdIsPercentEncodedIntoThePath() {
        let request = GeminiRequest.urlRequest(model: " my model/../x?y=1 ", apiKey: "k", body: Data(), timeout: 60)
        let url = request.url?.absoluteString
        #expect(url == "https://generativelanguage.googleapis.com/v1beta/models/my%20model%2F..%2Fx%3Fy=1:generateContent")
    }

    @Test func timeoutIsAMinuteAtLeastAndTenAtMost() {
        #expect(GeminiLimits.timeout(forAudioSeconds: 0) == 60)
        #expect(GeminiLimits.timeout(forAudioSeconds: 30) == 90)
        #expect(GeminiLimits.timeout(forAudioSeconds: 540) == 600)
        #expect(GeminiLimits.timeout(forAudioSeconds: 1800) == 600)
        #expect(GeminiLimits.timeout(forAudioSeconds: -5) == 60)
        #expect(GeminiLimits.timeout(forAudioSeconds: .nan) == 60)
    }

    @Test func outputTokensGrowWithTheAudioWithinBounds() {
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 0) == 8192)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: -10) == 8192)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 60) == 8192 + 1920)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1000) == 8192 + 32_000)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1800) == 65_536)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1_000_000) == 65_536)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: .infinity) == 8192)
    }

    @Test @MainActor func knownModelsAreTheOnesOfferedInSettings() {
        #expect(GeminiLimits.knownModels == Set(VoiceSettings.modelPresets.map(\.id)))
    }

    @Test func aCustomModelGetsAtMost8192OutputTokens() {
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1800, model: "my-custom-model") == 8192)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1800, model: "gemini-4") == 8192)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 0, model: "my-custom-model") == 8192)
    }

    @Test func aPresetModelKeepsTheFullCap() {
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1800, model: "gemini-3.8-flash") == 65_536)
        #expect(GeminiLimits.maxOutputTokens(forAudioSeconds: 1800, model: " models/gemini-3.5-flash-lite ") == 65_536)
    }

    @Test func fitsInlineUntilTheBase64AndMarginReachTheLimit() {
        #expect(GeminiLimits.fitsInline(audioBytes: 0))
        #expect(GeminiLimits.fitsInline(audioBytes: 7_000_000))
        // (n + 2) / 3 * 4 + 65_536 <= 20_000_000  <=>  n <= 14_950_848
        #expect(GeminiLimits.fitsInline(audioBytes: 14_950_848))
        #expect(!GeminiLimits.fitsInline(audioBytes: 14_950_849))
        #expect(!GeminiLimits.fitsInline(audioBytes: 20_000_000))
        #expect(!GeminiLimits.fitsInline(audioBytes: -1))
    }
}
