import Foundation

struct LyricBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var japanese: String
    var korean: String
    var startTime: Double?
    var endTime: Double?
    var confidence: Double?
    var isManuallyAdjusted: Bool
    var isAnchor: Bool

    init(
        id: UUID = UUID(),
        japanese: String,
        korean: String,
        startTime: Double? = nil,
        endTime: Double? = nil,
        confidence: Double? = nil,
        isManuallyAdjusted: Bool = false,
        isAnchor: Bool = false
    ) {
        self.id = id
        self.japanese = japanese
        self.korean = korean
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isManuallyAdjusted = isManuallyAdjusted
        self.isAnchor = isAnchor
    }

    // Custom Decodable for backward compatibility (old files lack isAnchor)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        japanese = try container.decode(String.self, forKey: .japanese)
        korean = try container.decode(String.self, forKey: .korean)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        isManuallyAdjusted = try container.decodeIfPresent(Bool.self, forKey: .isManuallyAdjusted) ?? false
        isAnchor = try container.decodeIfPresent(Bool.self, forKey: .isAnchor) ?? false
    }

    var hasTimingData: Bool {
        startTime != nil && endTime != nil
    }

    var isLowConfidence: Bool {
        guard let c = confidence else { return true }
        return c < 0.5
    }

    var durationString: String {
        guard let start = startTime, let end = endTime else { return "—" }
        return "\(TimeFormatter.format(start)) → \(TimeFormatter.format(end))"
    }
}
