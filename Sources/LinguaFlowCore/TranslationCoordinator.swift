import Foundation

public struct TranslationRequest: Equatable, Sendable {
    public let sourceText: String
    public let revision: UInt64

    public init(sourceText: String, revision: UInt64) {
        self.sourceText = sourceText
        self.revision = revision
    }
}

public struct TranslationResult: Equatable, Sendable {
    public let sourceText: String
    public let translatedText: String
    public let revision: UInt64

    public init(sourceText: String, translatedText: String, revision: UInt64) {
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.revision = revision
    }
}

public protocol TranslationProviding: Sendable {
    func translate(_ request: TranslationRequest) async throws -> String
    func cancel() async
}

public extension TranslationProviding {
    func cancel() async {}
}

@MainActor
public final class TranslationCoordinator {
    public var onResult: ((TranslationResult) -> Void)?
    public var onError: ((Error) -> Void)?

    private let provider: any TranslationProviding
    private let debounce: Duration
    private var activeRevision: UInt64?
    private var translationTask: Task<Void, Never>?

    public init(
        provider: any TranslationProviding,
        debounce: Duration = .milliseconds(400)
    ) {
        self.provider = provider
        self.debounce = debounce
    }

    public func submit(_ snapshot: SentenceSnapshot) {
        translationTask?.cancel()
        activeRevision = snapshot.revision

        let provider = self.provider
        let debounce = self.debounce
        let request = TranslationRequest(
            sourceText: snapshot.text,
            revision: snapshot.revision
        )

        translationTask = Task { [weak self] in
            do {
                if debounce != .zero {
                    try await Task.sleep(for: debounce)
                }

                let translatedText = try await provider.translate(request)
                try Task.checkCancellation()

                guard let self, self.activeRevision == request.revision else { return }
                self.onResult?(
                    TranslationResult(
                        sourceText: request.sourceText,
                        translatedText: translatedText,
                        revision: request.revision
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeRevision == request.revision else { return }
                self.onError?(error)
            }
        }
    }

    public func cancel() {
        activeRevision = nil
        translationTask?.cancel()
        translationTask = nil

        let provider = self.provider
        Task {
            await provider.cancel()
        }
    }
}
