import Foundation
import Translation

@main
struct LinguaFlowTranslationChecks {
    static func main() async throws {
        let source = Locale.Language(identifier: "zh-Hans")
        let target = Locale.Language(identifier: "en")
        let status = await LanguageAvailability().status(from: source, to: target)

        switch status {
        case .installed:
            let session = TranslationSession(installedSource: source, target: target)
            let response = try await session.translate("你好，很高兴认识你。")
            print("LinguaFlow Translation check passed: \(response.targetText)")
        case .supported:
            print("LinguaFlow Translation models are supported but not installed")
            exit(2)
        case .unsupported:
            print("LinguaFlow Translation language pair is unsupported")
            exit(1)
        @unknown default:
            print("LinguaFlow Translation status is unknown")
            exit(1)
        }
    }
}
