import Testing
@testable import QuickNote

struct GeminiNoticeTests {
    @Test func aRejectedKeyHasItsOwnMessage() {
        #expect(GeminiNotice.message(for: .badKey) == "Gemini didn't accept the API key — saved the on-device text.")
    }

    @Test func offlineAndQuotaHaveTheirOwnMessages() {
        #expect(GeminiNotice.message(for: .offline) == "No connection — saved the on-device text.")
        #expect(GeminiNotice.message(for: .quota) == "Gemini quota reached — saved the on-device text.")
    }

    @Test func everythingElseIsCouldntTranscribe() {
        for error in [GeminiError.server, .blocked, .truncated, .malformed, .empty, .tooLarge] {
            #expect(GeminiNotice.message(for: error) == "Gemini couldn't transcribe this — saved the on-device text.")
        }
    }

    @Test func withoutOnDeviceTextTheMessageDoesNotClaimItWasSaved() {
        #expect(GeminiNotice.message(for: .offline, savedOnDevice: false) == "No connection.")
        #expect(GeminiNotice.message(for: .server, savedOnDevice: false) == "Gemini couldn't transcribe this.")
    }

    @Test func aUnknownModelHasItsOwnMessage() {
        #expect(GeminiNotice.message(for: .badModel) == "Gemini doesn't know this model — saved the on-device text.")
    }

    @Test func onlyARejectedKeyOrModelOffersSettings() {
        #expect(GeminiNotice.offersSettings(for: .badKey))
        #expect(GeminiNotice.offersSettings(for: .badModel))
        for error in [GeminiError.quota, .server, .blocked, .truncated, .malformed, .empty, .tooLarge, .offline, .mismatch] {
            #expect(!GeminiNotice.offersSettings(for: error))
        }
    }

    @Test func aKeptRecordingMessageSaysSoAndGivesTheReason() {
        #expect(GeminiNotice.keptMessage(for: .gemini(.badKey), savedOnDevice: true)
            == "Gemini couldn't transcribe — recording kept. The API key wasn't accepted. On-device text saved.")
        #expect(GeminiNotice.keptMessage(for: .gemini(.offline), savedOnDevice: true)
            == "Gemini couldn't transcribe — recording kept. No connection. On-device text saved.")
    }

    @Test func aKeptRecordingMessageSaysSoEvenWithoutAnyText() {
        for error in [GeminiError.badKey, .badModel, .quota, .server, .blocked, .truncated, .malformed, .tooLarge, .offline, .mismatch] {
            let message = GeminiNotice.keptMessage(for: .gemini(error), savedOnDevice: false)
            #expect(message.contains("recording kept"))
            #expect(!message.contains("On-device text saved"))
        }
    }

    @Test func aRecordingThatCouldNotBeKeptIsNotClaimedToBe() {
        #expect(GeminiNotice.keptMessage(for: .gemini(.offline), savedOnDevice: true, recordingKept: false)
            == "Gemini couldn't transcribe — the recording couldn't be kept. No connection. On-device text saved.")
        #expect(GeminiNotice.keptMessage(for: .keyUnreadable, savedOnDevice: false, recordingKept: false)
            == "Couldn't read the Gemini key from the Keychain — the recording couldn't be kept.")
        #expect(GeminiNotice.keptMessage(for: .stoppedWaiting, savedOnDevice: false, recordingKept: false)
            == "Stopped waiting for Gemini — the recording couldn't be kept.")
    }

    @Test func otherKeptReasonsHaveTheirOwnMessages() {
        #expect(GeminiNotice.keptMessage(for: .keyUnreadable, savedOnDevice: false)
            == "Couldn't read the Gemini key from the Keychain — recording kept.")
        #expect(GeminiNotice.keptMessage(for: .stoppedWaiting, savedOnDevice: true)
            == "Stopped waiting for Gemini — recording kept. On-device text saved.")
    }

    @Test func keptReasonsOfferSettingsOnlyForTheKeyAndModel() {
        #expect(GeminiNotice.offersSettings(for: KeptReason.gemini(.badKey)))
        #expect(GeminiNotice.offersSettings(for: KeptReason.gemini(.badModel)))
        #expect(!GeminiNotice.offersSettings(for: KeptReason.gemini(.quota)))
        #expect(!GeminiNotice.offersSettings(for: KeptReason.keyUnreadable))
        #expect(!GeminiNotice.offersSettings(for: KeptReason.stoppedWaiting))
    }
}
