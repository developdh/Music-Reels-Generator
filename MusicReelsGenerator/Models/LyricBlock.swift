import Foundation

struct LyricBlock: Identifiable, Codable, Equatable {
    let id: UUID
    var japanese: String
    var korean: String
    var startTime: Double?
    var endTime: Double?
    var confidence: Double?
    var isManuallyAdjusted: Bool

    init(
        id: UUID = UUID(),
        japanese: String,
        korean: String,
        startTime: Double? = nil,
        endTime: Double? = nil,
        confidence: Double? = nil,
        isManuallyAdjusted: Bool = false
    ) {
        self.id = id
        self.japanese = japanese
        self.korean = korean
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.isManuallyAdjusted = isManuallyAdjusted
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
