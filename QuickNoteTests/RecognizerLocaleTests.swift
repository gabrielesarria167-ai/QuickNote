import Testing
@testable import QuickNote

struct RecognizerLocaleTests {
    private let supported: Set<String> = ["en_US", "en_GB", "en_AU", "it_IT", "zh_CN", "zh_TW", "de_DE"]

    private func choose(_ current: String, _ preferred: [String] = [], chosen: String? = nil) -> String? {
        RecognizerLocale.choose(current: current, preferred: preferred, supported: supported, chosen: chosen)
    }

    @Test func exactMatchWins() {
        #expect(choose("it_IT") == "it_IT")
        #expect(choose("en_GB") == "en_GB")
    }

    @Test func dashesAndUnderscoresAreTheSame() {
        #expect(choose("en-AU") == "en_AU")
    }

    @Test func unsupportedRegionFallsBackToTheUsualOneOfTheLanguage() {
        #expect(choose("en_IT") == "en_US")
    }

    @Test func regionOverrideSuffixIsIgnored() {
        #expect(choose("en_GB@rg=itzzzz") == "en_GB")
        #expect(choose("it_IT@calendar=gregorian") == "it_IT")
        #expect(RecognizerLocale.choose(current: "it_IT", preferred: [], supported: ["it_IT@rg=chzzzz"]) == "it_IT@rg=chzzzz")
    }

    @Test func scriptIsIgnored() {
        #expect(choose("zh-Hans-CN") == "zh_CN")
        #expect(choose("zh-Hant-TW") == "zh_TW")
    }

    @Test func currentLocaleComesBeforePreferredLanguages() {
        #expect(choose("en_IT", ["it-IT"]) == "en_US")
    }

    @Test func preferredLanguagesAreTriedWhenTheCurrentOneIsNotSupported() {
        #expect(choose("xx_XX", ["yy-YY", "it-IT"]) == "it_IT")
    }

    @Test func nothingSupportedGivesNil() {
        #expect(choose("xx_XX", ["yy-YY"]) == nil)
        #expect(RecognizerLocale.choose(current: "en_US", preferred: [], supported: []) == nil)
    }

    @Test func aChosenLanguageIsTriedFirst() {
        #expect(choose("en_US", ["it-IT"], chosen: "de-DE") == "de_DE")
        #expect(choose("en_US", chosen: "it-IT") == "it_IT")
    }

    @Test func aChosenLanguageWithAnUnsupportedRegionUsesTheUsualOne() {
        #expect(choose("it_IT", chosen: "en-IT") == "en_US")
    }

    @Test func anUnsupportedChosenLanguageFallsBackToTheCurrentOne() {
        #expect(choose("it_IT", chosen: "ja-JP") == "it_IT")
        #expect(choose("xx_XX", ["it-IT"], chosen: "ja-JP") == "it_IT")
    }

    @Test func noChosenLanguageChangesNothing() {
        #expect(choose("en_GB", chosen: nil) == "en_GB")
    }
}
