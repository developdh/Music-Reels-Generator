import Foundation

enum UILanguage: String, CaseIterable, Codable, Identifiable {
    case ko, en, ja

    var id: String { rawValue }

    /// Self-referential display name (always in the target language)
    var displayName: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        case .ja: return "日本語"
        }
    }
}
