import Foundation

enum CropMode: String, Codable, CaseIterable, Identifiable {
    case vertical = "vertical"     // 세로모드: cover crop (기존 동작)
    case horizontal = "horizontal" // 가로모드: fit + blur background

    var id: String { rawValue }
}

/// Output canvas shape. Combined with `OutputResolution` to produce final pixel dimensions.
enum OutputAspectRatio: String, Codable, CaseIterable, Identifiable {
    case vertical9_16 = "vertical9_16"     // 9:16 — Reels / Shorts / TikTok
    case portrait4_5 = "portrait4_5"       // 4:5 — Instagram feed portrait
    case square1_1 = "square1_1"           // 1:1 — Instagram feed square
    case horizontal16_9 = "horizontal16_9" // 16:9 — YouTube horizontal

    var id: String { rawValue }

    /// Pixel (width, height) given the canonical short-edge size.
    func dimensions(shortEdge: Int) -> (width: Int, height: Int) {
        switch self {
        case .vertical9_16:   return (shortEdge, shortEdge * 16 / 9)
        case .portrait4_5:    return (shortEdge, shortEdge * 5 / 4)
        case .square1_1:      return (shortEdge, shortEdge)
        case .horizontal16_9: return (shortEdge * 16 / 9, shortEdge)
        }
    }

    /// W:H label for display (e.g. "9:16").
    var ratioLabel: String {
        switch self {
        case .vertical9_16:   return "9:16"
        case .portrait4_5:    return "4:5"
        case .square1_1:      return "1:1"
        case .horizontal16_9: return "16:9"
        }
    }

    /// Closest preset for raw width/height (used to migrate legacy projects).
    static func from(width: Int, height: Int) -> OutputAspectRatio {
        guard width > 0, height > 0 else { return .vertical9_16 }
        let target = Double(width) / Double(height)
        let candidates: [(OutputAspectRatio, Double)] = [
            (.vertical9_16, 9.0 / 16.0),
            (.portrait4_5, 4.0 / 5.0),
            (.square1_1, 1.0),
            (.horizontal16_9, 16.0 / 9.0)
        ]
        return candidates.min(by: { abs($0.1 - target) < abs($1.1 - target) })?.0 ?? .vertical9_16
    }
}

/// Output quality, expressed as the short-edge pixel count. Long edge is derived from aspect.
enum OutputResolution: String, Codable, CaseIterable, Identifiable {
    case full = "full"        // 1080 short edge — current default
    case compact = "compact"  // 720  short edge — smaller files

    var id: String { rawValue }

    var shortEdge: Int {
        switch self {
        case .full:    return 1080
        case .compact: return 720
        }
    }

    /// Display label like "1080p".
    var label: String {
        "\(shortEdge)p"
    }
}

struct CropSettings: Codable, Equatable {
    var mode: CropMode = .vertical
    var horizontalOffset: Double = 0.0 // -1.0 (left) to 1.0 (right), 0 = center
    var verticalOffset: Double = 0.0   // -1.0 (top) to 1.0 (bottom), 0 = center
    var zoomScale: Double = 1.0        // 1.0 (no zoom) to 3.0 (3x zoom)
    var blurRadius: Double = 20.0      // 가로모드 blur intensity (10–50)
    var outputAspectRatio: OutputAspectRatio = .vertical9_16
    var outputResolution: OutputResolution = .full

    var outputWidth: Int {
        outputAspectRatio.dimensions(shortEdge: outputResolution.shortEdge).width
    }
    var outputHeight: Int {
        outputAspectRatio.dimensions(shortEdge: outputResolution.shortEdge).height
    }
    /// width / height as a Double for layout math.
    var outputAspectFraction: Double {
        Double(outputWidth) / Double(outputHeight)
    }

    enum CodingKeys: String, CodingKey {
        case mode, horizontalOffset, verticalOffset, zoomScale, blurRadius
        case outputAspectRatio, outputResolution
        // Legacy keys (decode-only)
        case outputWidth, outputHeight
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

        if let ar = try container.decodeIfPresent(OutputAspectRatio.self, forKey: .outputAspectRatio) {
            outputAspectRatio = ar
        } else if let w = try container.decodeIfPresent(Int.self, forKey: .outputWidth),
                  let h = try container.decodeIfPresent(Int.self, forKey: .outputHeight) {
            outputAspectRatio = .from(width: w, height: h)
        } else {
            outputAspectRatio = .vertical9_16
        }
        outputResolution = try container.decodeIfPresent(OutputResolution.self, forKey: .outputResolution)
            ?? .full
    }

    init() {}

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(horizontalOffset, forKey: .horizontalOffset)
        try c.encode(verticalOffset, forKey: .verticalOffset)
        try c.encode(zoomScale, forKey: .zoomScale)
        try c.encode(blurRadius, forKey: .blurRadius)
        try c.encode(outputAspectRatio, forKey: .outputAspectRatio)
        try c.encode(outputResolution, forKey: .outputResolution)
    }
}
