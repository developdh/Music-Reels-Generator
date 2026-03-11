import Foundation

struct TrimSettings: Codable, Equatable {
    var startTime: Double = 0
    var endTime: Double = 0

    /// Whether the user has trimmed away from full duration.
    /// We consider trim "active" only if start > 0 or end is meaningfully less than what was set.
    /// The caller should check against the source duration for full accuracy.
    func isActive(sourceDuration: Double) -> Bool {
        startTime > 0.1 || (endTime > 0 && endTime < sourceDuration - 0.1)
    }

    /// Trimmed duration
    var duration: Double {
        max(0, endTime - startTime)
    }

    /// Validate and clamp to source duration
    mutating func clamp(to sourceDuration: Double) {
        startTime = max(0, min(startTime, sourceDuration))
        endTime = max(startTime + 0.1, min(endTime, sourceDuration))
    }

    /// Reset to full source duration
    mutating func reset(sourceDuration: Double) {
        startTime = 0
        endTime = sourceDuration
    }

    /// Initialize with default full-duration range
    static func fullDuration(_ duration: Double) -> TrimSettings {
        TrimSettings(startTime: 0, endTime: duration)
    }
}
