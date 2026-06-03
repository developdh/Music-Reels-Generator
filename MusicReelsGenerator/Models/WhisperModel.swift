import Foundation

/// Whisper.cpp recognition model.
///
/// `.auto` picks the best installed model; explicit cases map to a
/// `ggml-<rawValue>.bin` file. Empirically, on hard Japanese / Vocaloid audio,
/// **large-v3 (full) > medium > large-v3-turbo** — turbo's 4-layer distilled
/// decoder degrades on difficult vocals — so `.auto` prefers large-v3 first and
/// ranks turbo below medium (see `WhisperAlignmentService.autoQualityOrder`).
enum WhisperModel: String, Codable, CaseIterable, Identifiable {
    case auto
    case largeV3 = "large-v3"
    case medium
    case largeV3Turbo = "large-v3-turbo"
    case small
    case base

    var id: String { rawValue }

    /// ggml filename for an explicit model; `nil` for `.auto`.
    var ggmlFilename: String? {
        self == .auto ? nil : "ggml-\(rawValue).bin"
    }
}
