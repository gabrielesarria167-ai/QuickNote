import SwiftUI
@preconcurrency import Speech

/// The Settings window (⌘,): the Gemini key and model, and the language of on-device recognition.
struct SettingsView: View {
    @Bindable var settings: VoiceSettings
    @State private var keyInput = ""
    @State private var isCustomModel = false
    @State private var languages: [VoiceLanguage] = []

    private var modelSelection: Binding<String> {
        Binding(
            get: {
                isCustomModel || !VoiceSettings.modelPresets.contains { $0.id == settings.geminiModel }
                    ? Self.customTag
                    : settings.geminiModel
            },
            set: { tag in
                if tag == Self.customTag {
                    isCustomModel = true
                } else {
                    isCustomModel = false
                    settings.geminiModel = tag
                }
            }
        )
    }

    private static let customTag = "custom"

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $keyInput, prompt: Text("Paste your Gemini API key"))
                    .onSubmit(save)
                HStack {
                    Button("Save", action: save)
                        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if settings.hasGeminiKey {
                        Button("Remove", role: .destructive) { settings.removeKey() }
                        Label("Key saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                if let error = settings.keyError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Link("Get a key in Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
                Picker("Model", selection: modelSelection) {
                    ForEach(VoiceSettings.modelPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                    Text("Custom…").tag(Self.customTag)
                }
                if modelSelection.wrappedValue == Self.customTag {
                    TextField("Model ID", text: $settings.geminiModel, prompt: Text(VoiceSettings.defaultModel))
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Gemini")
            } footer: {
                Text("With a key, each voice note's audio is sent to Google's Gemini API to transcribe it in any language and give it a title. On the free tier Google may use it to improve its products and people may review it; on a paid tier it doesn't. Without a key, everything stays on your Mac.")
            }

            Section {
                Picker("Language", selection: $settings.onDeviceLanguage) {
                    Text("Automatic").tag(String?.none)
                    ForEach(languages) { language in
                        Text(language.name).tag(String?.some(language.id))
                    }
                }
            } header: {
                Text("On-device recognition")
            } footer: {
                Text("Used for the live text while you speak, and for the note when there's no Gemini key.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings.refreshKeyState()
            isCustomModel = !VoiceSettings.modelPresets.contains { $0.id == settings.geminiModel }
            let supported = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier))
            languages = VoiceLanguage.available(supported: supported)
        }
    }

    private func save() {
        settings.saveKey(keyInput)
        if settings.keyError == nil { keyInput = "" }
    }
}
