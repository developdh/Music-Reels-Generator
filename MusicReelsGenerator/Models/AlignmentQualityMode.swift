import Foundation

enum AlignmentQualityMode: String, Codable, CaseIterable, Identifiable {
    case fast = "Fast"
    case balanced = "Balanced"
    case accurate = "Accurate"
    case maximum = "Maximum"

    var id: String { rawValue }

    /// Beam width for DP search
    var beamWidth: Int {
        switch self {
        case .fast: return 30
        case .balanced: return 80
        case .accurate: return 200
        case .maximum: return 500
        }
    }

    /// Minimum text similarity to consider a candidate
    var matchThreshold: Double {
        switch self {
        case .fast: return 0.30
        case .balanced: return 0.25
        case .accurate: return 0.20
        case .maximum: return 0.15
        }
    }

    /// How many consecutive whisper segments can be combined for one block
    var maxCombineSegments: Int {
        switch self {
        case .fast: return 2
        case .balanced: return 3
        case .accurate: return 4
        case .maximum: return 5
        }
    }

    /// Search window radius in seconds around expected position
    var searchWindowSeconds: Double {
        switch self {
        case .fast: return 20
        case .balanced: return 30
        case .accurate: return 45
        case .maximum: return 60
        }
    }

    /// Number of refinement passes
    var refinementPasses: Int {
        switch self {
        case .fast: return 1
        case .balanced: return 2
        case .accurate: return 3
        case .maximum: return 3
        }
    }

    /// Weight of positional scoring (0 = text only, 1 = position dominates)
    var positionWeight: Double {
        switch self {
        case .fast: return 0.3
        case .balanced: return 0.35
        case .accurate: return 0.4
        case .maximum: return 0.4
        }
    }

    /// Description for UI
    var description: String {
        switch self {
        case .fast: return "Quick alignment, lower accuracy"
        case .balanced: return "Good balance of speed and accuracy"
        case .accurate: return "Higher accuracy, slower processing"
        case .maximum: return "Best accuracy, significantly slower"
        }
    }
}
