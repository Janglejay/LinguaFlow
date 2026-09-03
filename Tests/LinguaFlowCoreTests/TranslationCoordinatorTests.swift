import XCTest
@testable import LinguaFlowCore

private actor ControlledTranslationProvider: TranslationProviding {
    private var continuations: [UInt64: CheckedContinuation<String, Error>] = [:]

    func translate(_ request: TranslationRequest) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            continuations[request.revision] = continuation
        }
    }

    func complete(revision: UInt64, with text: String) {
        continuations.removeValue(forKey: revision)?.resume(returning: text)
    }

    func waitUntilRequested(revision: UInt64) async {
        while continuations[revision] == nil {
            await Task.yield()
        }
    }
}

@MainActor
final class TranslationCoordinatorTests: XCTestCase {
    func testOnlyPublishesTheNewestRevision() async {
        let provider = ControlledTranslationProvider()
        let coordinator = TranslationCoordinator(provider: provider, debounce: .zero)
        var results: [TranslationResult] = []
        coordinator.onResult = { results.append($0) }

        coordinator.submit(.init(text: "第一句", revision: 1, isFinal: false))
        await provider.waitUntilRequested(revision: 1)
        coordinator.submit(.init(text: "第二句", revision: 2, isFinal: false))
        await provider.waitUntilRequested(revision: 2)

        await provider.complete(revision: 1, with: "stale")
        await provider.complete(revision: 2, with: "the second sentence")

        for _ in 0..<20 where results.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(results, [
            .init(sourceText: "第二句", translatedText: "the second sentence", revision: 2),
        ])
    }

    func testCancelPreventsALateResultFromPublishing() async {
        let provider = ControlledTranslationProvider()
        let coordinator = TranslationCoordinator(provider: provider, debounce: .zero)
        var results: [TranslationResult] = []
        coordinator.onResult = { results.append($0) }

        coordinator.submit(.init(text: "私密内容", revision: 9, isFinal: false))
        await provider.waitUntilRequested(revision: 9)
        coordinator.cancel()
        await provider.complete(revision: 9, with: "private content")

        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(results.isEmpty)
    }
}
