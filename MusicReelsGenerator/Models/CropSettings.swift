import Foundation

enum CropMode: String, Codable, CaseIterable, Identifiable {
    case vertical = "vertical"     // 세로모드: cover crop (기존 동작)
    case horizontal = "horizontal" // 가로모드: fit + blur background

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vertical: return "세로모드"
        case .horizontal: return "가로모드"
        }
    }
}

struct CropSettings: Codable, Equatable {
    var mode: CropMode = .vertical
    var horizontalOffset: Double = 0.0 // -1.0 (left) to 1.0 (right), 0 = center
    var verticalOffset: Double = 0.0   // -1.0 (top) to 1.0 (bottom), 0 = center
    var zoomScale: Double = 1.0        // 1.0 (no zoom) to 3.0 (3x zoom)
    var blurRadius: Double = 20.0      // 가로모드 blur intensity (10–50)
    var outputWidth: Int = 1080
    var outputHeight: Int = 1920

    var aspectRatio: Double {
        Double(outputWidth) / Double(outputHeight)
    }

    // Backward-compatible decoding
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy files may have "center"/"manual" — map both to .vertical
        if let rawMode = try container.decodeIfPresent(String.self, forKey: .mode) {
            switch rawMode {
            case "horizontal":
                mode = .horizontal
            default:
                mode = .vertical
            }
        } else {
            mode = .vertical
        }
        horizontalOffset = try container.decodeIfPresent(Double.self, forKey: .horizontalOffset) ?? 0.0
        verticalOffset = try container.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? 0.0
        zoomScale = try container.decodeIfPresent(Double.self, forKey: .zoomScale) ?? 1.0
        blurRadius = try container.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 20.0
        outputWidth = try container.decodeIfPresent(Int.self, forKey: .outputWidth) ?? 1080
        outputHeight = try container.decodeIfPresent(Int.self, forKey: .outputHeight) ?? 1920
    }

    init() {}
}
