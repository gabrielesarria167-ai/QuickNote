import Foundation

/// Sends a recording to Gemini and gets back its transcript and a title.
///
/// The network is behind `transport`, so tests give it a fake one. Never logs the key, the URL or the
/// audio.
struct GeminiTranscriber: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    var transport: Transport = GeminiTranscriber.urlSessionTransport
    /// How long to wait before the one retry after a quota or server error.
    var retryDelay: Duration = .seconds(2)

    /// Transcribes the audio file, with one retry after `retryDelay` if Gemini says it is busy
    /// (`.quota`, `.server`). Reads the file and builds the request off the main actor.
    ///
    /// Throws `GeminiError` for every failure Gemini or the network can cause (an unreadable or empty
    /// file is `.empty`, a file too big for one request `.tooLarge`), and `CancellationError` if the
    /// task is cancelled, so callers can tell "the user gave up" from "it failed".
    nonisolated func transcribe(
        audioURL: URL,
        mimeType: String = "audio/aac",
        duration: TimeInterval,
        apiKey: String,
        model: String
    ) async throws -> Transcription {
        guard let audio = try? Data(contentsOf: audioURL, options: .mappedIfSafe), !audio.isEmpty else {
            throw GeminiError.empty
        }
        guard GeminiLimits.fitsInline(audioBytes: audio.count) else {
            throw GeminiError.tooLarge
        }
        let body = try? GeminiRequest.body(
            audio: audio,
            mimeType: mimeType,
            prompt: GeminiRequest.prompt,
            maxOutputTokens: GeminiLimits.maxOutputTokens(forAudioSeconds: duration)
        )
        guard let body else { throw GeminiError.malformed }
        let request = GeminiRequest.urlRequest(
            model: model,
            apiKey: apiKey,
            body: body,
            timeout: GeminiLimits.timeout(forAudioSeconds: duration)
        )

        var result = try await attempt(request)
        if case .failure(let error) = result, error == .quota || error == .server {
            try await Task.sleep(for: retryDelay)
            result = try await attempt(request)
        }
        return try result.get()
    }

    private nonisolated func attempt(_ request: URLRequest) async throws -> Result<Transcription, GeminiError> {
        try Task.checkCancellation()
        do {
            let (data, response) = try await transport(request)
            return GeminiResponse.parse(data: data, statusCode: response.statusCode)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                return .failure(.offline)
            default:
                return .failure(.server)
            }
        } catch {
            return .failure(.server)
        }
    }

    /// A fresh ephemeral session per request: no cookies or cache kept, and it fails at once when
    /// offline instead of waiting for a connection.
    static let urlSessionTransport: Transport = { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
