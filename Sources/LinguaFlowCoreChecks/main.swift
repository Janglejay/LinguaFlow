import CoreGraphics
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

        try expect(
            LiveTranslationDraft.sourceText(
                committed: .init(text: "我今天", revision: 1, isFinal: false),
                provisionalCandidate: "想去公园"
            ),
            "我今天想去公园",
            "translate the highlighted candidate before commit"
        )
        try expect(
            LiveTranslationDraft.sourceText(
                committed: .init(text: "上一句。", revision: 2, isFinal: true),
                provisionalCandidate: "下一句"
            ),
            "下一句",
            "do not mix a finished sentence into the next live preview"
        )

        let compactSize = UnifiedPanelLayout.size(
            contentWidths: [42, 156, 38],
            rowHeights: [20, 30, 20]
        )
        try expect(compactSize.width <= 260, true, "short content stays compact")
        try expect(compactSize.height, 102, "three rows use stable spacing")

        let below = UnifiedPanelLayout.origin(
            anchor: .init(x: 480, y: 420, width: 0, height: 22),
            panelSize: .init(width: 240, height: 102),
            visibleFrame: .init(x: 0, y: 0, width: 1440, height: 900)
        )
        try expect(below, .init(x: 480, y: 312), "place panel below the insertion point")

        let above = UnifiedPanelLayout.origin(
            anchor: .init(x: 480, y: 18, width: 0, height: 22),
            panelSize: .init(width: 240, height: 102),
            visibleFrame: .init(x: 0, y: 0, width: 1440, height: 900)
        )
        try expect(above, .init(x: 480, y: 46), "flip above near the screen bottom")

        print("LinguaFlow core checks passed")
    }
}
