import Foundation
import LinguaFlowCore

private enum CheckFailure: Error, CustomStringConvertible {
    case mismatch(String)

    var description: String {
        switch self {
        case .mismatch(let message): message
        }
    }
}

private func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
    guard actual == expected else {
        throw CheckFailure.mismatch("\(label): expected \(expected), got \(actual)")
    }
}

private actor ImmediateProvider: TranslationProviding {
    func translate(_ request: TranslationRequest) async throws -> String {
        "English: \(request.sourceText)"
    }
}

@main
@MainActor
struct LinguaFlowCoreChecks {
    static func main() async throws {
        var buffer = CommittedSentenceBuffer(maxCharacters: 8)
        try expect(
            buffer.append("我今天"),
            SentenceSnapshot(text: "我今天", revision: 1, isFinal: false),
            "append first chunk"
        )
        try expect(
            buffer.append("去公园。"),
            SentenceSnapshot(text: "我今天去公园。", revision: 2, isFinal: true),
            "finalize sentence"
        )
        try expect(
            buffer.append("明天"),
            SentenceSnapshot(text: "明天", revision: 3, isFinal: false),
            "start a fresh sentence"
        )
        try expect(
            buffer.removeLastCharacter(),
            SentenceSnapshot(text: "明", revision: 4, isFinal: false),
            "mirror host backspace"
        )

        let provider = ImmediateProvider()
        let coordinator = TranslationCoordinator(provider: provider, debounce: .zero)
        var received: TranslationResult?
        coordinator.onResult = { received = $0 }
        coordinator.submit(.init(text: "你好", revision: 5, isFinal: false))

        for _ in 0..<100 where received == nil {
            await Task.yield()
        }

        try expect(
            received,
            TranslationResult(sourceText: "你好", translatedText: "English: 你好", revision: 5),
            "publish current translation"
        )

        print("LinguaFlow core checks passed")
    }
}
