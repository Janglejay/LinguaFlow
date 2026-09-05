import AppKit
import Foundation

struct EnglishSpellingCorrection: Equatable {
    let original: String
    let replacement: String
    let range: NSRange
}

@MainActor
final class EnglishSpellChecker {
    private let checker = NSSpellChecker.shared
    private let language = "en_US"

    func candidates(for partialWord: String, limit: Int = 5) -> [String] {
        guard
            limit > 0,
            partialWord.count >= 2,
            shouldOfferCorrection(for: partialWord)
        else {
            return []
        }

        let range = NSRange(location: 0, length: partialWord.utf16.count)
        var suggestions = checker.completions(
            forPartialWordRange: range,
            in: partialWord,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? []

        if suggestions.isEmpty {
            suggestions = checker.guesses(
                forWordRange: range,
                in: partialWord,
                language: language,
                inSpellDocumentWithTag: 0
            ) ?? []
        }

        var seen = Set<String>()
        return suggestions.compactMap { suggestion in
            let value = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = value.lowercased()
            guard
                !value.isEmpty,
                value.count <= 32,
                shouldOfferCorrection(for: value),
                seen.insert(key).inserted
            else {
                return nil
            }
            return value
        }.prefix(limit).map { $0 }
    }

    func firstCorrection(in text: String) -> EnglishSpellingCorrection? {
        guard !text.isEmpty else { return nil }

        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let misspelledRange = checker.checkSpelling(
            of: text,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        guard
            misspelledRange.location != NSNotFound,
            NSMaxRange(misspelledRange) <= fullRange.length,
            let stringRange = Range(misspelledRange, in: text)
        else {
            return nil
        }

        let original = String(text[stringRange])
        guard shouldOfferCorrection(for: original) else { return nil }

        let replacement = checker.correction(
            forWordRange: misspelledRange,
            in: text,
            language: language,
            inSpellDocumentWithTag: 0
        ) ?? checker.guesses(
            forWordRange: misspelledRange,
            in: text,
            language: language,
            inSpellDocumentWithTag: 0
        )?.first

        guard
            let replacement,
            !replacement.isEmpty,
            replacement.caseInsensitiveCompare(original) != ComparisonResult.orderedSame
        else {
            return nil
        }

        return EnglishSpellingCorrection(
            original: original,
            replacement: replacement,
            range: misspelledRange
        )
    }

    private func shouldOfferCorrection(for word: String) -> Bool {
        guard word.count > 1 else { return false }
        return word.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar) || scalar == "'"
        }
    }
}
