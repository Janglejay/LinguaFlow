public enum TranslationDirection: String, Equatable, Sendable {
    case chineseToEnglish
    case englishToChinese

    public var sourceLanguageIdentifier: String {
        switch self {
        case .chineseToEnglish: "zh-Hans"
        case .englishToChinese: "en"
        }
    }

    public var targetLanguageIdentifier: String {
        switch self {
        case .chineseToEnglish: "en"
        case .englishToChinese: "zh-Hans"
        }
    }

    public var sourceLabel: String {
        switch self {
        case .chineseToEnglish: "中文"
        case .englishToChinese: "EN"
        }
    }

    public var targetLabel: String {
        switch self {
        case .chineseToEnglish: "EN"
        case .englishToChinese: "中文"
        }
    }
}
