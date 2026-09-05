import Foundation

public struct EnglishCandidateContext: Equatable, Sendable {
    public let word: String
    public let range: NSRange

    public init(word: String, range: NSRange) {
        self.word = word
        self.range = range
    }

    public static func trailingWord(
        in text: String,
        minimumLength: Int = 2
    ) -> EnglishCandidateContext? {
        guard !text.isEmpty else { return nil }

        var start = text.endIndex
        while start > text.startIndex {
            let previous = text.index(before: start)
            guard isEnglishWordCharacter(text[previous]) else { break }
            start = previous
        }

        guard start < text.endIndex else { return nil }
        let word = String(text[start...])
        guard word.count >= minimumLength else { return nil }

        return EnglishCandidateContext(
            word: word,
            range: NSRange(start..<text.endIndex, in: text)
        )
    }

    private static func isEnglishWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.letters.contains(scalar) || scalar == "'" || scalar == "’"
        }
    }
}

public enum EnglishCandidateAction: Equatable, Sendable {
    case passThrough
    case dismiss
    case select(index: Int)
    case highlight(index: Int)
}

public enum EnglishCandidateInteraction {
    public static func action(
        keyCode: UInt16,
        characters: String?,
        candidateCount: Int,
        highlightedIndex: Int,
        hasShift: Bool,
        hasControl: Bool
    ) -> EnglishCandidateAction {
        guard candidateCount > 0, !hasShift, !hasControl else {
            return .passThrough
        }

        switch keyCode {
        case 48:
            return .select(index: min(max(0, highlightedIndex), candidateCount - 1))
        case 53:
            return .dismiss
        case 123, 126:
            let current = min(max(0, highlightedIndex), candidateCount - 1)
            return .highlight(index: (current - 1 + candidateCount) % candidateCount)
        case 124, 125:
            let current = min(max(0, highlightedIndex), candidateCount - 1)
            return .highlight(index: (current + 1) % candidateCount)
        default:
            guard
                let characters,
                characters.count == 1,
                let digit = characters.first?.wholeNumberValue,
                digit > 0,
                digit <= candidateCount
            else {
                return .passThrough
            }
            return .select(index: digit - 1)
        }
    }
}
