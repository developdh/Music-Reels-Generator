import Foundation

enum AlignmentQualityMode: String, Codable, CaseIterable, Identifiable {
    case legacy = "Recommended"
    case baseline = "Exp: Segment"
    case refined = "Exp: Refined"
    case experimental = "Exp: Hybrid"

    var id: String { rawValue }

    /// Whether this mode uses the production whisper-cpp CLI pipeline (Swift-only)
    var usesLegacyPipeline: Bool {
        self == .legacy
    }

    /// Whether this mode routes through the experimental Python pipeline
    var usesAdvancedPipeline: Bool {
        !usesLegacyPipeline
    }

    /// Whether this is an experimental (non-production) mode
    var isExperimental: Bool {
        self != .legacy
    }

    /// Mode name passed to the Python pipeline
    var pipelineModeName: String {
        switch self {
        case .legacy:       return "fast"
        case .baseline:     return "baseline"
        case .refined:      return "refined"
        case .experimental: return "experimental"
        }
    }

    /// Whisper model override for the Python pipeline (nil = use pipeline default)
    var whisperModelOverride: String? {
        return nil
    }

    // MARK: - Legacy pipeline parameters (used by WhisperAlignmentService)

    var beamWidth: Int { 80 }
    var matchThreshold: Double { 0.25 }
    var maxCombineSegments: Int { 3 }
    var searchWindowSeconds: Double { 30 }
    var refinementPasses: Int { 2 }
    var positionWeight: Double { 0.35 }

    /// Description for UI
    var description: String {
        switch self {
        case .legacy:
            return "Production: whisper-cpp segment matching (recommended)"
        case .baseline:
            return "Experimental: Python segment-level Levenshtein matching"
        case .refined:
            return "Experimental: Python baseline + gated local refinement"
        case .experimental:
            return "Experimental: Python ungated hybrid pipeline"
        }
    }
}
