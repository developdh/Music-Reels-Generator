import Foundation

/// Converts source-absolute lyric timing to export-relative timing across one or
/// more concatenated trim ranges.
enum TrimTimingUtility {
    /// Convert a source-absolute time to export-relative time across all ranges.
    /// Returns nil if the time falls outside every kept range.
    static func toExportTime(_ sourceTime: Double, trim: TrimSettings) -> Double? {
        var offset = 0.0
        for range in trim.sortedRanges {
            if sourceTime >= range.startTime && sourceTime <= range.endTime {
                return offset + (sourceTime - range.startTime)
            }
            offset += range.duration
        }
        return nil
    }

    /// Filter and remap lyric blocks for export across one or more trim ranges.
    /// - Blocks fully outside every range are omitted.
    /// - Blocks overlapping a range are clamped to that range's portion.
    /// - A block straddling multiple ranges produces multiple output blocks (one per overlap),
    ///   sharing the same UUID — they render the same image, just at different output times.
    /// - All times are remapped to export-relative coordinates (the concatenated output).
    /// - When the trim has a crossfade, each consecutive range is overlapped by the crossfade
    ///   duration so block timings shift earlier accordingly.
    static func blocksForExport(
        _ blocks: [LyricBlock],
        trim: TrimSettings
    ) -> [LyricBlock] {
        var output: [LyricBlock] = []
        var cumulativeOffset = 0.0
        let xfade = trim.effectiveCrossfade
        for (i, range) in trim.sortedRanges.enumerated() {
            let rangeStartInOutput = cumulativeOffset - Double(i) * xfade
            for block in blocks {
                guard let bs = block.startTime, let be = block.endTime else { continue }
                let overlapStart = max(bs, range.startTime)
                let overlapEnd = min(be, range.endTime)
                guard overlapEnd > overlapStart else { continue }

                var clamped = block
                clamped.startTime = rangeStartInOutput + (overlapStart - range.startTime)
                clamped.endTime = rangeStartInOutput + (overlapEnd - range.startTime)
                output.append(clamped)
            }
            cumulativeOffset += range.duration
        }
        return output
    }
}
