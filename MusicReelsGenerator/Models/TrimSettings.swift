import Foundation

/// A single time range to keep in the trimmed output.
/// Multiple ranges are concatenated in order during export.
struct TrimRange: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var startTime: Double
    var endTime: Double
    /// Optional human label (e.g. "Verse 1", "Chorus"). Not rendered in v1; reserved for future.
    var label: String?

    init(id: UUID = UUID(), startTime: Double, endTime: Double, label: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
    }

    var duration: Double {
        max(0, endTime - startTime)
    }
}

struct TrimSettings: Codable, Equatable {
    /// Ordered, non-overlapping ranges. The exported video concatenates them in order.
    /// A single full-duration range is the default (= "no trimming").
    var ranges: [TrimRange]

    init(ranges: [TrimRange] = []) {
        self.ranges = ranges
    }

    // MARK: - Convenience accessors (single-range compat)

    /// First range start. Setting writes to the first range (creates one if empty).
    /// Used by toolbar/playback code that hasn't been migrated to range IDs.
    var startTime: Double {
        get { ranges.first?.startTime ?? 0 }
        set {
            ensureNonEmpty()
            ranges[0].startTime = newValue
        }
    }

    /// Last range end. Setting writes to the last range.
    var endTime: Double {
        get { ranges.last?.endTime ?? 0 }
        set {
            ensureNonEmpty()
            let i = ranges.count - 1
            ranges[i].endTime = newValue
        }
    }

    /// Sum of all range durations. This is the duration of the concatenated export.
    var duration: Double {
        ranges.reduce(0.0) { $0 + $1.duration }
    }

    /// Sorted copy of the ranges (defensive: editing should keep them sorted, but this guarantees it).
    var sortedRanges: [TrimRange] {
        ranges.sorted { $0.startTime < $1.startTime }
    }

    /// Index of the range containing this source-absolute time, if any.
    func index(containing sourceTime: Double) -> Int? {
        ranges.firstIndex { $0.startTime <= sourceTime && sourceTime < $0.endTime }
    }

    /// Range immediately following the given source-absolute time, by start time.
    func nextRange(after sourceTime: Double) -> TrimRange? {
        sortedRanges.first { $0.startTime > sourceTime + 0.01 }
    }

    /// Whether the user has trimmed away from full duration.
    func isActive(sourceDuration: Double) -> Bool {
        if ranges.isEmpty { return false }
        if ranges.count > 1 { return true }
        guard let only = ranges.first else { return false }
        return only.startTime > 0.1 || only.endTime < sourceDuration - 0.1
    }

    /// Reset to a single range covering the full source duration.
    mutating func reset(sourceDuration: Double) {
        ranges = [TrimRange(startTime: 0, endTime: sourceDuration)]
    }

    /// Validate and clamp every range to source duration; drop zero-length ranges.
    mutating func clamp(to sourceDuration: Double) {
        for i in ranges.indices {
            ranges[i].startTime = max(0, min(ranges[i].startTime, sourceDuration))
            ranges[i].endTime = max(ranges[i].startTime + 0.1,
                                    min(ranges[i].endTime, sourceDuration))
        }
        ranges.removeAll { $0.duration < 0.05 }
    }

    static func fullDuration(_ duration: Double) -> TrimSettings {
        TrimSettings(ranges: [TrimRange(startTime: 0, endTime: duration)])
    }

    private mutating func ensureNonEmpty() {
        if ranges.isEmpty {
            ranges.append(TrimRange(startTime: 0, endTime: 0))
        }
    }

    // MARK: - Codable (backward compat)

    enum CodingKeys: String, CodingKey {
        case ranges
        // Legacy single-range keys
        case startTime, endTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try c.decodeIfPresent([TrimRange].self, forKey: .ranges) {
            ranges = r
        } else if let s = try c.decodeIfPresent(Double.self, forKey: .startTime),
                  let e = try c.decodeIfPresent(Double.self, forKey: .endTime) {
            ranges = [TrimRange(startTime: s, endTime: e)]
        } else {
            ranges = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ranges, forKey: .ranges)
    }
}
