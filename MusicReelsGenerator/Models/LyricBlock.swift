import Foundation

struct LyricBlock: Identifiable, Equatable {
    let id: UUID
    var japanese: String
    var korean: String
    var startTime: Double?
    var endTime: Double?
    var confidence: Double?
    var manuallyAdjustedStart: Bool
    var manuallyAdjustedEnd: Bool
    /// Set by alignment service based on textScore, used for alignment internal logic
    var isAnchor: Bool
    /// Set only by user via setAnchor(), used for piecewise correction
    var isUserAnchor: Bool

    /// True if either start or end was manually adjusted
    var isManuallyAdjusted: Bool {
        manuallyAdjustedStart || manuallyAdjustedEnd
    }

    /// True if this block should be treated as a hard timing constraint for correction.
    /// Only user-set anchors and fully manually adjusted blocks qualify.
    var isTrustedAnchor: Bool {
        isUserAnchor || (manuallyAdjustedStart && manuallyAdjustedEnd)
    }

    init(
        id: UUID = UUID(),
        japanese: String,
        korean: String,
        startTime: Double? = nil,
        endTime: Double? = nil,
        confidence: Double? = nil,
        manuallyAdjustedStart: Bool = false,
        manuallyAdjustedEnd: Bool = false,
        isAnchor: Bool = false,
        isUserAnchor: Bool = false
    ) {
        self.id = id
        self.japanese = japanese
        self.korean = korean
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.manuallyAdjustedStart = manuallyAdjustedStart
        self.manuallyAdjustedEnd = manuallyAdjustedEnd
        self.isAnchor = isAnchor
        self.isUserAnchor = isUserAnchor
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

// MARK: - Codable with backward compatibility

extension LyricBlock: Codable {
    enum CodingKeys: String, CodingKey {
        case id, japanese, korean, startTime, endTime, confidence
        case manuallyAdjustedStart, manuallyAdjustedEnd
        case isManuallyAdjusted // legacy key for backward compat decode only
        case isAnchor, isUserAnchor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        japanese = try container.decode(String.self, forKey: .japanese)
        korean = try container.decode(String.self, forKey: .korean)
        startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Double.self, forKey: .endTime)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        isAnchor = try container.decodeIfPresent(Bool.self, forKey: .isAnchor) ?? false
        // Backward compat: old files without isUserAnchor — treat isAnchor as user anchor
        isUserAnchor = try container.decodeIfPresent(Bool.self, forKey: .isUserAnchor) ?? isAnchor

        // New granular fields with backward compat from legacy isManuallyAdjusted
        if let adjStart = try container.decodeIfPresent(Bool.self, forKey: .manuallyAdjustedStart) {
            manuallyAdjustedStart = adjStart
            manuallyAdjustedEnd = try container.decodeIfPresent(Bool.self, forKey: .manuallyAdjustedEnd) ?? false
        } else {
            // Legacy: single isManuallyAdjusted maps to both
            let legacy = try container.decodeIfPresent(Bool.self, forKey: .isManuallyAdjusted) ?? false
            manuallyAdjustedStart = legacy
            manuallyAdjustedEnd = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(japanese, forKey: .japanese)
        try container.encode(korean, forKey: .korean)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(manuallyAdjustedStart, forKey: .manuallyAdjustedStart)
        try container.encode(manuallyAdjustedEnd, forKey: .manuallyAdjustedEnd)
        try container.encode(isAnchor, forKey: .isAnchor)
        try container.encode(isUserAnchor, forKey: .isUserAnchor)
    }
}
