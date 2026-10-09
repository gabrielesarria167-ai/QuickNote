import Foundation

/// The request that asks Gemini to transcribe a recording and title it. The audio goes inline, as
/// base64, in the JSON body; the API key goes in a header, never in the URL or the body.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct GeminiRequest: Encodable {
    struct Content: Encodable {
        var role: String
        var parts: [Part]
    }

    /// Either text or inline data; the one that isn't used is left out of the JSON.
    struct Part: Encodable {
        var text: String?
        var inlineData: InlineData?
    }

    struct InlineData: Encodable {
        var mimeType: String
        /// The audio, base64 encoded.
        var data: String
    }

    struct SchemaField: Encodable {
        var type: String
    }

    struct Schema: Encodable {
        var type: String
        var properties: [String: SchemaField]
        var required: [String]
        var propertyOrdering: [String]
    }

    struct GenerationConfig: Encodable {
        var responseMimeType: String
        var responseSchema: Schema
        var maxOutputTokens: Int
    }

    var contents: [Content]
    var generationConfig: GenerationConfig

    static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/"

    /// What Gemini is told to do with the audio.
    static let prompt = """
        Transcribe the audio verbatim, in the language or languages actually spoken. Never translate. \
        If the speaker switches language, keep each part in the language it was spoken in.
        The transcript is plain text only: no Markdown, no speaker labels, no timestamps. \
        Start a new paragraph when the speaker changes or after a long pause. \
        Leave out filler sounds such as "um" and "uh". \
        If there is no speech, return an empty transcript.
        The title is a short descriptive title of at most 8 words, in the main language spoken, \
        with no quotes and no trailing period.
        """

    /// The JSON body for one recording.
    static func body(audio: Data, mimeType: String, prompt: String, maxOutputTokens: Int) throws -> Data {
        let request = GeminiRequest(
            contents: [
                Content(role: "user", parts: [
                    Part(text: prompt),
                    Part(inlineData: InlineData(mimeType: mimeType, data: audio.base64EncodedString())),
                ]),
            ],
            generationConfig: GenerationConfig(
                responseMimeType: "application/json",
                responseSchema: Schema(
                    type: "OBJECT",
                    properties: ["title": SchemaField(type: "STRING"), "transcript": SchemaField(type: "STRING")],
                    required: ["title", "transcript"],
                    propertyOrdering: ["title", "transcript"]
                ),
                maxOutputTokens: maxOutputTokens
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(request)
    }

    /// The model id as it goes in the URL: without surrounding whitespace or the `models/` that
    /// Google's own model lists put in front.
    static func normalizedModel(_ model: String) -> String {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.hasPrefix("models/") ? String(id.dropFirst("models/".count)) : id
    }

    /// A POST of `body` to the model's `generateContent` endpoint. The model id is percent-encoded
    /// into the path, and the key is sent in the `x-goog-api-key` header only.
    static func urlRequest(model: String, apiKey: String, body: Data, timeout: TimeInterval) -> URLRequest {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        let id = normalizedModel(model)
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        // Every character that could break a URL is percent-encoded above, so this can't be nil.
        var request = URLRequest(url: URL(string: endpoint + encoded + ":generateContent")!, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = body
        return request
    }
}

/// How big a request may be, and how long it may take, for a recording of a given size and length.
enum GeminiLimits {
    /// Gemini's limit for a whole request with inline data.
    static let maxRequestBytes = 20_000_000

    /// Room kept for the prompt, the schema and the JSON around the audio.
    private static let marginBytes = 64 * 1024

    /// Whether audio of this size, base64 encoded (4/3 as big) plus a margin, fits in one request.
    static func fitsInline(audioBytes: Int) -> Bool {
        guard audioBytes >= 0 else { return false }
        let base64Bytes = (audioBytes + 2) / 3 * 4
        return base64Bytes + marginBytes <= maxRequestBytes
    }

    /// How long to wait for an answer: a minute, plus a second per second of audio, at most ten minutes.
    static func timeout(forAudioSeconds seconds: TimeInterval) -> TimeInterval {
        max(60, min(600, 60 + clamped(seconds)))
    }

    /// The models offered in Settings, which accept up to 65 536 output tokens.
    static let knownModels: Set<String> = ["gemini-3.8-flash", "gemini-3.5-flash-lite"]

    /// A generous cap on the answer's length: at least 8192 tokens, plus 32 per second of audio
    /// (far more than speech needs), and never more than the models allow. For a `model` typed in
    /// by hand the cap is 8192, which every model accepts; a larger one can be refused with a 400.
    static func maxOutputTokens(forAudioSeconds seconds: TimeInterval, model: String? = nil) -> Int {
        let tokens = min(65_536, 8192 + Int(clamped(seconds) * 32))
        guard let model, !knownModels.contains(GeminiRequest.normalizedModel(model)) else { return tokens }
        return min(tokens, 8192)
    }

    /// Keeps negative, infinite and NaN durations from reaching the arithmetic above.
    private static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? min(max(0, seconds), 86_400) : 0
    }
}
