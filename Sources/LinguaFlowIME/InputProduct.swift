import Foundation
import LinguaFlowCore

enum InputProduct {
    case chinese
    case english

    static var current: InputProduct {
        let configuredMode = Bundle.main.object(
            forInfoDictionaryKey: "LinguaFlowInputMode"
        ) as? String
        return configuredMode == "English" ? .english : .chinese
    }

    var translationDirection: TranslationDirection {
        switch self {
        case .chinese: .chineseToEnglish
        case .english: .englishToChinese
        }
    }

    var usesRime: Bool {
        self == .chinese
    }
}
