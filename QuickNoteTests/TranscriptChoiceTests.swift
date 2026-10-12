import Testing
@testable import QuickNote

struct TranscriptChoiceTests {
    @Test func geminiIsUsedWhenItSucceeded() {
        let choice = TranscriptChoice.choose(
            gemini: .success(Transcription(title: "Trip plan", transcript: "Buy tickets.")),
            apple: "by tickets"
        )
        #expect(choice.title == "Trip plan")
        #expect(choice.text == "Buy tickets.")
        #expect(choice.notice == nil)
    }

    @Test func geminisTitleIsCleaned() {
        let choice = TranscriptChoice.choose(
            gemini: .success(Transcription(title: "# \"Trip plan.\"", transcript: "Buy tickets.")),
            apple: "by tickets"
        )
        #expect(choice.title == "Trip plan")
    }

    @Test func aBlankTitleIsNil() {
        let choice = TranscriptChoice.choose(
            gemini: .success(Transcription(title: " ", transcript: "Buy tickets.")),
            apple: "by tickets"
        )
        #expect(choice.title == nil)
        #expect(choice.text == "Buy tickets.")
        #expect(choice.notice == nil)
    }

    @Test func appleTextIsUsedWithoutATitleWhenGeminiFailed() {
        for error in [GeminiError.badKey, .quota, .server, .blocked, .truncated, .malformed, .empty, .tooLarge, .offline, .mismatch] {
            let choice = TranscriptChoice.choose(gemini: .failure(error), apple: "  by tickets \n")
            #expect(choice.title == nil)
            #expect(choice.text == "by tickets")
            #expect(choice.notice == error)
        }
    }

    @Test func appleTextIsUsedQuietlyWhenGeminiWasNotAsked() {
        let choice = TranscriptChoice.choose(gemini: nil, apple: "by tickets")
        #expect(choice.title == nil)
        #expect(choice.text == "by tickets")
        #expect(choice.notice == nil)
    }

    @Test func aSuccessWithoutTextFallsBackToApple() {
        let choice = TranscriptChoice.choose(gemini: .success(Transcription(title: "x", transcript: " ")), apple: "by tickets")
        #expect(choice.title == nil)
        #expect(choice.text == "by tickets")
        #expect(choice.notice == .empty)
    }

    @Test func nothingFromEitherGivesEmptyText() {
        #expect(TranscriptChoice.choose(gemini: .failure(.empty), apple: " ").text == "")
        #expect(TranscriptChoice.choose(gemini: nil, apple: "").text == "")
    }

    @Test func geminiIsAskedOnlyWithAudioOfSomeLengthAndAKey() {
        #expect(TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 3, hasKey: true))
        #expect(TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 0.5, hasKey: true))
        #expect(!TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 0.49, hasKey: true))
        #expect(!TranscriptChoice.shouldTranscribe(hasAudio: false, duration: 3, hasKey: true))
        #expect(!TranscriptChoice.shouldTranscribe(hasAudio: true, duration: 3, hasKey: false))
    }

    private func words(_ count: Int) -> String {
        let pool = ["we", "should", "meet", "tomorrow", "morning", "to", "talk", "about", "the", "plan", "for", "our", "trip", "and", "book", "tickets"]
        return (0..<count).map { pool[$0 % pool.count] }.joined(separator: " ")
    }

    private let english = "I think we should meet tomorrow morning to talk about the plan for the trip, " +
        "and then book the tickets, the hotel and the car before the prices go up again next week."

    @Test func aTextInAnotherLanguageIsNotComparedByWordCount() {
        #expect(TranscriptChoice.wordCount(english) >= 20)
        #expect(!TranscriptChoice.looksCutShort(gemini: "明日の朝に会って、旅行の計画について話しましょう。", apple: english))
        #expect(!TranscriptChoice.looksCutShort(gemini: "我们明天早上见面，谈谈旅行的计划。", apple: english))
    }

    @Test func chineseAndJapaneseWordsAreCountedWithoutSpaces() {
        #expect(TranscriptChoice.wordCount("明日の朝に会って旅行の計画について話しましょう") > 3)
        #expect(TranscriptChoice.wordCount("我们明天早上见面谈谈旅行的计划") > 3)
    }

    @Test func aTooShortTextIsNotTakenForAnotherLanguage() {
        #expect(TranscriptChoice.wordCount(english) >= 20)
        #expect(TranscriptChoice.looksCutShort(gemini: "OK so", apple: english))
    }

    @Test func aCutShortTextInTheSameLanguageIsStillCaught() {
        #expect(TranscriptChoice.looksCutShort(gemini: "I think we should meet tomorrow morning.", apple: english))
    }

    @Test func wordsAreCountedOnWhitespace() {
        #expect(TranscriptChoice.wordCount("") == 0)
        #expect(TranscriptChoice.wordCount("  one two\nthree\t four ") == 4)
    }

    @Test func aTranscriptUnderSixtyPercentOfApplesLooksCutShort() {
        #expect(TranscriptChoice.looksCutShort(gemini: words(11), apple: words(20)))
        #expect(!TranscriptChoice.looksCutShort(gemini: words(12), apple: words(20)))
        #expect(!TranscriptChoice.looksCutShort(gemini: words(100), apple: words(20)))
    }

    @Test func aShortAppleTextIsNotComparedWith() {
        #expect(!TranscriptChoice.looksCutShort(gemini: "", apple: words(19)))
        #expect(!TranscriptChoice.looksCutShort(gemini: "", apple: ""))
        #expect(TranscriptChoice.looksCutShort(gemini: "", apple: words(20)))
    }

    @Test func theLongerAnswerWins() {
        let short = Transcription(title: "a", transcript: words(3))
        let long = Transcription(title: "b", transcript: words(9))
        #expect(TranscriptChoice.longer(short, long) == long)
        #expect(TranscriptChoice.longer(long, short) == long)
        let tie = Transcription(title: "c", transcript: words(3))
        #expect(TranscriptChoice.longer(short, tie) == short)
    }

    /// Roughly what Apple heard of a work session, mishearings included.
    private let workSession = "okay so today I need to finish the login page for the shop and then check why " +
        "the shift button doesn't ask for a pin, and after that I'll call Paola about the orders for next " +
        "week because the noticeboard still shows the old to do list and nobody updated it since Monday"

    /// Gemini's transcript of the same session: better punctuation, a few words heard differently.
    private let workSessionGemini = "Okay, so today I need to finish the login page for the shop, and then check " +
        "why the shift button doesn't ask for a PIN. And after that, I'll call Paola about the orders for next " +
        "week, because the notice board still shows the old to-do list and nobody's updated it since Monday."

    /// What Gemini once answered instead of a real recording.
    private let invented = "Hello, my name is John. Today is Tuesday, the 23rd of February 2021. " +
        "And this is a voice recording for the sound of my life website."

    @Test func anInventedTranscriptLooksUnrelated() {
        #expect(TranscriptChoice.looksUnrelated(gemini: invented, apple: workSession))
    }

    @Test func aRealTranscriptWithMishearingsIsNotUnrelated() {
        #expect(!TranscriptChoice.looksUnrelated(gemini: workSessionGemini, apple: workSession))
    }

    @Test func aTranscriptThatIsOnlyCutShortIsNotUnrelated() {
        let start = "Okay, so today I need to finish the login page for the shop, and then check why the shift button"
        #expect(!TranscriptChoice.looksUnrelated(gemini: start, apple: workSession))
    }

    @Test func unrelatedNeedsEnoughAppleTextInTheSameLanguage() {
        #expect(!TranscriptChoice.looksUnrelated(gemini: invented, apple: "okay so today I need to finish"))
        #expect(!TranscriptChoice.looksUnrelated(gemini: invented, apple: ""))
        #expect(!TranscriptChoice.looksUnrelated(
            gemini: "Oggi devo finire la pagina di accesso per l'officina e poi controllare il pulsante dei turni.",
            apple: workSession
        ))
        #expect(!TranscriptChoice.looksUnrelated(gemini: "", apple: workSession))
    }

    @Test func theAnswerThatMatchesWinsOverALongerInventedOne() {
        let real = Transcription(title: "Work", transcript: "Okay, so today I need to finish the login page for the shop.")
        let fake = Transcription(title: "John", transcript: invented + " " + invented)
        #expect(TranscriptChoice.better(fake, real, apple: workSession) == real)
        #expect(TranscriptChoice.better(real, fake, apple: workSession) == real)
        let full = Transcription(title: "Work", transcript: workSessionGemini)
        #expect(TranscriptChoice.better(real, full, apple: workSession) == full)
    }

    /// What Apple's recognizer, set to English, made of Spanish speech: it reads as Spanish at only 0.8.
    private let spanishHeardAsEnglish = "Bueno so a la mejor yo tango que yamar a Paola Mañana for los pedidos " +
        "they la semana that he gets a porque el tablet oh no se actually so the tienda a la nada"

    /// The same, but reading as English with full confidence.
    private let spanishHeardAsClearEnglish = "OK so a whole I had a key to me now the pa he now they log in pa " +
        "la tienda and they go a see by K L botton day turn those no pee the pin"

    @Test func aRealTranscriptIsNotRejectedForAnAppleTextInTheWrongLanguage() {
        let spanish = "Bueno, a lo mejor yo tengo que llamar a Paola mañana por los pedidos de la semana que viene, " +
            "porque la tablet no sé, la verdad, y la tienda no tiene nada."
        #expect(!TranscriptChoice.looksUnrelated(gemini: spanish, apple: spanishHeardAsEnglish))
        #expect(!TranscriptChoice.looksUnrelated(gemini: spanish, apple: spanishHeardAsClearEnglish))
    }

    @Test func anInventedEnglishTextIsCaughtAgainstClearlyEnglishGibberish() {
        #expect(TranscriptChoice.looksUnrelated(gemini: invented, apple: spanishHeardAsClearEnglish))
    }

    @Test func apostrophesAccentsAndCaseDoNotMakeWordsDifferent() {
        #expect(TranscriptChoice.words("Doesn’t DOESN'T doesnt") == ["doesnt", "doesnt", "doesnt"])
        #expect(TranscriptChoice.words("Página pagina") == ["pagina", "pagina"])
    }

    @Test func curlyApostrophesDoNotMakeARealTranscriptLookUnrelated() {
        let curly = workSession.replacingOccurrences(of: "'", with: "’")
        #expect(!TranscriptChoice.looksUnrelated(gemini: curly, apple: workSession))
    }
}
