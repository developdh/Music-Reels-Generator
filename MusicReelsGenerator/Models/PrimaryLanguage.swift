import Foundation

enum PrimaryLanguage: String, Codable, CaseIterable, Identifiable {
    case japanese = "ja"
    case korean = "ko"
    case english = "en"
    case auto = "auto"

    var id: String { rawValue }

    /// Whisper language flag value (nil for auto-detect)
    var whisperLanguageFlag: String? {
        switch self {
        case .japanese: return "ja"
        case .korean: return "ko"
        case .english: return "en"
        case .auto: return nil
        }
    }
}
