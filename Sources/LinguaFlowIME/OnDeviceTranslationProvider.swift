import Foundation
import LinguaFlowCore

#if canImport(Translation)
@preconcurrency import Translation
#endif

enum OnDeviceTranslationError: LocalizedError {
    case frameworkUnavailable
    case languagesNotInstalled

    var errorDescription: String? {
        switch self {
        case .frameworkUnavailable:
            "当前构建没有启用 Apple Translation framework。"
        case .languagesNotInstalled:
            "请先在系统设置的“翻译语言”中下载中文和英语。"
        }
    }
}

#if canImport(Translation)
actor OnDeviceTranslationProvider: TranslationProviding {
    private let direction: TranslationDirection
    private var session: TranslationSession?

    init(direction: TranslationDirection) {
        self.direction = direction
    }

    func translate(_ request: TranslationRequest) async throws -> String {
        let activeSession = try await readySession()

        do {
            return try await activeSession.translate(request.sourceText).targetText
        } catch TranslationError.notInstalled {
            throw OnDeviceTranslationError.languagesNotInstalled
        }
    }

    func translateCandidates(_ sourceTexts: [String]) async throws -> [String: String] {
        guard !sourceTexts.isEmpty else { return [:] }
        let activeSession = try await readySession()
        let requests = sourceTexts.enumerated().map { index, sourceText in
            TranslationSession.Request(
                sourceText: sourceText,
                clientIdentifier: String(index)
            )
        }

        do {
            let responses = try await activeSession.translations(from: requests)
            var translated: [String: String] = [:]
            for response in responses {
                guard
                    let identifier = response.clientIdentifier,
                    let index = Int(identifier),
                    sourceTexts.indices.contains(index)
                else {
                    continue
                }
                let value = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    translated[sourceTexts[index].lowercased()] = value
                }
            }
            return translated
        } catch TranslationError.notInstalled {
            throw OnDeviceTranslationError.languagesNotInstalled
        }
    }

    func cancel() async {
        session?.cancel()
        session = nil
    }

    private func readySession() async throws -> TranslationSession {
        let activeSession: TranslationSession
        if let session {
            activeSession = session
        } else {
            let source = Locale.Language(identifier: direction.sourceLanguageIdentifier)
            let target = Locale.Language(identifier: direction.targetLanguageIdentifier)
            let created: TranslationSession
            if #available(macOS 26.4, *) {
                created = TranslationSession(
                    installedSource: source,
                    target: target,
                    preferredStrategy: .lowLatency
                )
            } else {
                created = TranslationSession(installedSource: source, target: target)
            }
            session = created
            activeSession = created
        }

        guard await activeSession.isReady else {
            throw OnDeviceTranslationError.languagesNotInstalled
        }
        return activeSession
    }
}
#else
actor OnDeviceTranslationProvider: TranslationProviding {
    init(direction: TranslationDirection) {}

    func translate(_ request: TranslationRequest) async throws -> String {
        throw OnDeviceTranslationError.frameworkUnavailable
    }

    func translateCandidates(_ sourceTexts: [String]) async throws -> [String: String] {
        throw OnDeviceTranslationError.frameworkUnavailable
    }
}
#endif
