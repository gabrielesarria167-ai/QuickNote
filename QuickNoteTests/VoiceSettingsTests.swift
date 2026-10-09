import Foundation
import Testing
@testable import QuickNote

@MainActor
struct VoiceSettingsTests {
    /// Settings on a throwaway defaults suite and an in-memory key store.
    private func makeSettings(key: String? = nil, defaults: UserDefaults? = nil) -> (VoiceSettings, UserDefaults) {
        let defaults = defaults ?? UserDefaults(suiteName: "VoiceSettingsTests-\(UUID().uuidString)")!
        return (VoiceSettings(keyStore: InMemoryKeyStore(key: key), defaults: defaults), defaults)
    }

    @Test func startsWithTheDefaults() {
        let (settings, _) = makeSettings()
        #expect(settings.geminiModel == "gemini-3.8-flash")
        #expect(settings.model == "gemini-3.8-flash")
        #expect(settings.onDeviceLanguage == nil)
        #expect(!settings.hasGeminiKey)
    }

    @Test func settingsAreKeptInDefaults() {
        let (settings, defaults) = makeSettings()
        settings.geminiModel = "gemini-3.5-flash-lite"
        settings.onDeviceLanguage = "it-IT"
        let (reopened, _) = makeSettings(defaults: defaults)
        #expect(reopened.geminiModel == "gemini-3.5-flash-lite")
        #expect(reopened.onDeviceLanguage == "it-IT")
        #expect(defaults.string(forKey: "geminiModel") == "gemini-3.5-flash-lite")
        #expect(defaults.string(forKey: "onDeviceLanguage") == "it-IT")
    }

    @Test func automaticLanguageRemovesTheStoredOne() {
        let (settings, defaults) = makeSettings()
        settings.onDeviceLanguage = "it-IT"
        settings.onDeviceLanguage = nil
        #expect(defaults.object(forKey: "onDeviceLanguage") == nil)
    }

    @Test func aBlankModelFallsBackToTheDefault() {
        let (settings, _) = makeSettings()
        settings.geminiModel = "  "
        #expect(settings.model == "gemini-3.8-flash")
        settings.geminiModel = " my-model \n"
        #expect(settings.model == "my-model")
    }

    @Test func theKeyStateIsNotLookedUpUntilAsked() {
        let (settings, _) = makeSettings(key: "abc")
        #expect(!settings.hasGeminiKey)
        settings.refreshKeyState()
        #expect(settings.hasGeminiKey)
    }

    @Test func savingAndRemovingTheKeyUpdatesTheState() throws {
        let (settings, _) = makeSettings()
        settings.saveKey(" abc \n")
        #expect(settings.hasGeminiKey)
        #expect(settings.keyError == nil)
        #expect(try settings.readKey() == "abc")
        settings.removeKey()
        #expect(!settings.hasGeminiKey)
        #expect(try settings.readKey() == nil)
    }

    @Test func aBlankKeyShowsAnError() {
        let (settings, _) = makeSettings()
        settings.saveKey("  ")
        #expect(!settings.hasGeminiKey)
        #expect(settings.keyError != nil)
        settings.saveKey("abc")
        #expect(settings.keyError == nil)
    }

    @Test func languageChoicesAreOfferedOnlyWhenSupported() {
        let supported: Set<String> = ["en_US", "it_IT", "es_MX", "de_DE", "pt_BR"]
        #expect(VoiceLanguage.available(supported: supported).map(\.id) == ["en-US", "it-IT", "es-ES", "de-DE"])
        #expect(VoiceLanguage.available(supported: []).isEmpty)
    }

    @Test func allLanguageChoicesAreTheOnesTheSettingsListPromises() {
        #expect(VoiceLanguage.all.map(\.id) == ["en-US", "it-IT", "es-ES", "ja-JP", "fr-FR", "de-DE"])
        #expect(VoiceLanguage.all.map(\.name) == ["English", "Italiano", "Español", "日本語", "Français", "Deutsch"])
    }
}
