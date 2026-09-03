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
    private var session: TranslationSession?

    func translate(_ request: TranslationRequest) async throws -> String {
        let activeSession: TranslationSession
        if let session {
            activeSession = session
        } else {
            let created = TranslationSession(
                installedSource: Locale.Language(identifier: "zh-Hans"),
                target: Locale.Language(identifier: "en")
            )
            session = created
            activeSession = created
        }

        guard await activeSession.isReady else {
            throw OnDeviceTranslationError.languagesNotInstalled
        }

        do {
            return try await activeSession.translate(request.sourceText).targetText
        } catch TranslationError.notInstalled {
            throw OnDeviceTranslationError.languagesNotInstalled
        }
    }

    func cancel() async {
        session?.cancel()
        session = nil
    }
}
#else
actor OnDeviceTranslationProvider: TranslationProviding {
    func translate(_ request: TranslationRequest) async throws -> String {
        throw OnDeviceTranslationError.frameworkUnavailable
    }
}
#endif
