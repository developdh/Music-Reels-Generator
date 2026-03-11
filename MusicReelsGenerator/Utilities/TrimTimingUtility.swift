import Foundation

/// Converts source-absolute lyric timing to trim-relative timing for export.
enum TrimTimingUtility {
    /// Convert a source-absolute time to trim-relative time.
    /// Returns nil if the time falls outside the trim range.
    static func toExportTime(_ sourceTime: Double, trim: TrimSettings) -> Double? {
        guard sourceTime >= trim.startTime && sourceTime <= trim.endTime else {
            return nil
        }
        return sourceTime - trim.startTime
    }

    /// Filter and remap lyric blocks for export within the trim range.
    /// - Blocks fully outside the range are omitted.
    /// - Blocks overlapping the range are clamped.
    /// - All times are shifted so trimStart becomes 0.
    static func blocksForExport(
        _ blocks: [LyricBlock],
        trim: TrimSettings
    ) -> [LyricBlock] {
        blocks.compactMap { block in
            guard let start = block.startTime, let end = block.endTime else {
                return nil
            }

            // Fully outside trim range — omit
            if end <= trim.startTime || start >= trim.endTime {
                return nil
            }

            // Clamp to trim range, then shift to export-relative time
            let clampedStart = max(start, trim.startTime) - trim.startTime
            let clampedEnd = min(end, trim.endTime) - trim.startTime

            var exported = block
            exported.startTime = clampedStart
            exported.endTime = clampedEnd
            return exported
        }
    }
}
