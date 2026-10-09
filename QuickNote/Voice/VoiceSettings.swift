import Foundation

/// A language the on-device recognizer can be set to listen in.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct VoiceLanguage: Identifiable, Equatable, Sendable {
    /// A locale identifier such as `it-IT`.
    let id: String
    /// The language's name in that language.
    let name: String

    static let all: [VoiceLanguage] = [
        VoiceLanguage(id: "en-US", name: "English"),
        VoiceLanguage(id: "it-IT", name: "Italiano"),
        VoiceLanguage(id: "es-ES", name: "Español"),
        VoiceLanguage(id: "ja-JP", name: "日本語"),
        VoiceLanguage(id: "fr-FR", name: "Français"),
        VoiceLanguage(id: "de-DE", name: "Deutsch"),
    ]

    /// The languages of `all` the recognizer supports, given the identifiers of its supported locales.
    /// A language counts when any region of it is supported (`es-ES` is offered if only `es_MX` is).
    static func available(supported: Set<String>) -> [VoiceLanguage] {
        all.filter { RecognizerLocale.choose(current: $0.id, preferred: [], supported: supported) != nil }
    }
}

/// What the user can set in the Settings window: the Gemini key and model, and the language of the
/// on-device recognizer. Settings are kept in `UserDefaults`, the key in the `KeyStore`.
@MainActor
@Observable
final class VoiceSettings {
    struct ModelPreset: Identifiable, Equatable {
        let id: String
        let title: String
    }

    static let defaultModel = "gemini-3.8-flash"
    static let modelPresets = [
        ModelPreset(id: "gemini-3.8-flash", title: "Gemini 3.8 Flash — best"),
        ModelPreset(id: "gemini-3.5-flash-lite", title: "Gemini 3.5 Flash-Lite — cheaper"),
    ]

    private static let modelKey = "geminiModel"
    private static let languageKey = "onDeviceLanguage"

    /// The model id as typed or picked. Use `model` to send a request.
    var geminiModel: String {
        didSet { defaults.set(geminiModel, forKey: Self.modelKey) }
    }

    /// A locale identifier from `VoiceLanguage.all`, or nil for Automatic (the system's language).
    var onDeviceLanguage: String? {
        didSet {
            if let onDeviceLanguage {
                defaults.set(onDeviceLanguage, forKey: Self.languageKey)
            } else {
                defaults.removeObject(forKey: Self.languageKey)
            }
        }
    }

    /// Whether a key is stored. Refreshed by `refreshKeyState`, `saveKey` and `removeKey`; it is not
    /// looked up when the settings are created, so nothing touches the Keychain until it is needed.
    private(set) var hasGeminiKey = false

    /// Why the last save or remove failed, for the Settings window.
    private(set) var keyError: String?

    @ObservationIgnored let keyStore: KeyStore
    @ObservationIgnored private let defaults: UserDefaults

    init(keyStore: KeyStore, defaults: UserDefaults = .standard) {
        self.keyStore = keyStore
        self.defaults = defaults
        geminiModel = defaults.string(forKey: Self.modelKey) ?? Self.defaultModel
        onDeviceLanguage = defaults.string(forKey: Self.languageKey)
    }

    /// The model to send requests to: `geminiModel` without surrounding whitespace, or the default
    /// if it is blank.
    var model: String {
        let trimmed = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultModel : trimmed
    }

    func refreshKeyState() {
        hasGeminiKey = keyStore.hasKey()
    }

    /// The stored key, or nil if there is none. Reads the Keychain the first time.
    func readKey() throws -> String? {
        try keyStore.read()
    }

    func saveKey(_ key: String) {
        do {
            try keyStore.save(key)
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
        refreshKeyState()
    }

    func removeKey() {
        do {
            try keyStore.delete()
            keyError = nil
        } catch {
            keyError = error.localizedDescription
        }
        refreshKeyState()
    }
}
