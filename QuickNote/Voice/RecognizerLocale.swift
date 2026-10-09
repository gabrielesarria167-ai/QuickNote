import Foundation

/// Picks which of the languages the speech recognizer supports to listen in.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
enum RecognizerLocale {
    /// Tries the language the user chose in Settings (if any), then the current locale, then each
    /// preferred language in order. For each, an exact match (language and region) wins; otherwise a
    /// supported locale of the same language, preferring the region that language is usually used in
    /// (so `en_IT` listens as `en_US`). Returns an identifier from `supported`, or nil if no
    /// candidate's language is supported.
    static func choose(current: String, preferred: [String], supported: Set<String>, chosen: String? = nil) -> String? {
        let options = supported.map { (identifier: $0, parts: parts(of: $0)) }
            .sorted { $0.identifier < $1.identifier }

        for candidate in (chosen.map { [$0] } ?? []) + [current] + preferred {
            let wanted = parts(of: candidate)
            if let exact = options.first(where: { $0.parts == wanted }) {
                return exact.identifier
            }
            let sameLanguage = options.filter { $0.parts.language == wanted.language }
            guard !sameLanguage.isEmpty else { continue }
            let usual = usualRegion(of: wanted.language)
            return (sameLanguage.first { $0.parts.region == usual } ?? sameLanguage[0]).identifier
        }
        return nil
    }

    private struct Parts: Equatable {
        var language: String
        var region: String?
    }

    /// Language and region of an identifier such as `en_US`, `en-US` or `zh-Hans-CN`. Anything from an
    /// `@` on (`en_GB@rg=itzzzz`, the system's region override) is left out.
    private static func parts(of identifier: String) -> Parts {
        let base = identifier.prefix { $0 != "@" }
        let pieces = base.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
        let language = pieces.first?.lowercased() ?? ""
        let region = pieces.dropFirst().last { piece in
            (piece.count == 2 && piece.allSatisfy(\.isLetter)) || (piece.count == 3 && piece.allSatisfy(\.isNumber))
        }
        return Parts(language: language, region: region?.uppercased())
    }

    private static func usualRegion(of language: String) -> String? {
        parts(of: Locale.Language(identifier: language).maximalIdentifier).region
    }
}
