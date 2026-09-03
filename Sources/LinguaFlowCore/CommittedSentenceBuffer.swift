import Foundation

public struct SentenceSnapshot: Equatable, Sendable {
    public let text: String
    public let revision: UInt64
    public let isFinal: Bool

    public init(text: String, revision: UInt64, isFinal: Bool) {
        self.text = text
        self.revision = revision
        self.isFinal = isFinal
    }
}

public struct CommittedSentenceBuffer: Sendable {
    public private(set) var revision: UInt64 = 0

    private let maxCharacters: Int
    private var text = ""
    private var startsNewSentenceOnNextAppend = false
    private var lastSnapshot: SentenceSnapshot?

    public init(maxCharacters: Int = 280) {
        precondition(maxCharacters > 0, "maxCharacters must be greater than zero")
        self.maxCharacters = maxCharacters
    }

    public var isEmpty: Bool {
        text.isEmpty
    }

    public var currentSnapshot: SentenceSnapshot? {
        lastSnapshot
    }

    @discardableResult
    public mutating func append(_ committedText: String) -> SentenceSnapshot? {
        guard !committedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if startsNewSentenceOnNextAppend {
            text.removeAll(keepingCapacity: true)
            startsNewSentenceOnNextAppend = false
        }

        text.append(committedText)
        if text.count > maxCharacters {
            text = String(text.suffix(maxCharacters))
        }

        revision &+= 1
        let isFinal = Self.endsSentence(text)
        let snapshot = SentenceSnapshot(text: text, revision: revision, isFinal: isFinal)
        lastSnapshot = snapshot
        startsNewSentenceOnNextAppend = isFinal
        return snapshot
    }

    @discardableResult
    public mutating func removeLastCharacter() -> SentenceSnapshot? {
        guard !text.isEmpty else { return nil }

        startsNewSentenceOnNextAppend = false
        text.removeLast()
        revision &+= 1

        guard !text.isEmpty else {
            lastSnapshot = nil
            return nil
        }

        let snapshot = SentenceSnapshot(
            text: text,
            revision: revision,
            isFinal: Self.endsSentence(text)
        )
        lastSnapshot = snapshot
        return snapshot
    }

    public mutating func reset() {
        text.removeAll(keepingCapacity: false)
        startsNewSentenceOnNextAppend = false
        lastSnapshot = nil
        revision &+= 1
    }

    private static func endsSentence(_ value: String) -> Bool {
        guard let character = value.last else { return false }
        return "。！？!?\n".contains(character)
    }
}
