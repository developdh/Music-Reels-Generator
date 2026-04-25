import Foundation

extension WhisperAlignmentService {
    /// Find vocal (speech) time ranges within a time window by looking at whisper segments.
    /// Returns sub-ranges where speech exists, excluding instrumental gaps longer than the threshold.
    /// Returns empty array if no speech segments exist in the range (pure instrumental).
    private static func vocalRanges(
        in segments: [WhisperSegment],
        from start: Double,
        to end: Double,
        gapThreshold: Double = 3.0
    ) -> [(start: Double, end: Double)] {
        // Collect segments that overlap with [start, end]
        let relevant = segments.filter { $0.endTime > start && $0.startTime < end }
        guard !relevant.isEmpty else {
            // No speech segments = pure instrumental — return empty
            print("[VocalRanges] No speech segments in \(String(format: "%.1f", start))–\(String(format: "%.1f", end))s — pure instrumental gap")
            return []
        }

        // Build vocal ranges by merging segments and splitting at large gaps
        var ranges: [(start: Double, end: Double)] = []
        var rangeStart = max(relevant[0].startTime, start)
        var rangeEnd = relevant[0].endTime

        for seg in relevant.dropFirst() {
            let segStart = seg.startTime
            let segEnd = seg.endTime
            if segStart - rangeEnd > gapThreshold {
                // Large gap = instrumental break — close current range, start new one
                ranges.append((start: rangeStart, end: min(rangeEnd, end)))
                rangeStart = max(segStart, start)
            }
            rangeEnd = max(rangeEnd, segEnd)
        }
        ranges.append((start: rangeStart, end: min(rangeEnd, end)))

        // Only extend edges by a small amount (up to 1s) to provide a little padding,
        // but never extend across large gaps
        let edgePadding = 1.0
        if !ranges.isEmpty {
            ranges[0].start = max(start, ranges[0].start - edgePadding)
            ranges[ranges.count - 1].end = min(end, ranges[ranges.count - 1].end + edgePadding)
        }

        return ranges
    }

    /// Estimate a reasonable display duration for a lyric line based on text length.
    /// Japanese singing typically runs ~3-6 characters per second.
    /// Returns a duration that covers the lyric but doesn't over-extend into gaps.
    private static func estimateLyricDuration(textLength: Int) -> Double {
        let chars = max(1, textLength)
        // ~4 chars/sec for Japanese singing, with a minimum of 1.5s and max of 8s
        let estimate = Double(chars) / 4.0
        return min(max(estimate, 1.5), 8.0)
    }

    /// Distribute blocks into vocal ranges, skipping instrumental gaps.
    /// Each block gets a duration based on its text length and singing speed estimate,
    /// NOT wall-to-wall filling. Gaps between lyric lines are preserved.
    static func distributeBlocksIntoVocalRanges(
        blocks: inout [LyricBlock],
        indices: Range<Int>,
        segments: [WhisperSegment],
        startBound: Double,
        endBound: Double,
        gapThreshold: Double = 3.0,
        confidence: Double = 0.05
    ) {
        let count = indices.count
        guard count > 0, endBound > startBound else { return }

        let ranges = vocalRanges(in: segments, from: startBound, to: endBound, gapThreshold: gapThreshold)
        let totalVocalDuration = ranges.reduce(0.0) { $0 + ($1.end - $1.start) }
        guard totalVocalDuration > 0 else { return }

        // Distribute block count across ranges proportional to range duration
        var rangeBlockCounts = ranges.map { range -> Int in
            let proportion = (range.end - range.start) / totalVocalDuration
            return max(0, Int((proportion * Double(count)).rounded()))
        }

        // Fix rounding: ensure total equals count
        let assigned = rangeBlockCounts.reduce(0, +)
        if assigned < count {
            if let maxIdx = rangeBlockCounts.indices.max(by: { rangeBlockCounts[$0] < rangeBlockCounts[$1] }) {
                rangeBlockCounts[maxIdx] += count - assigned
            }
        } else if assigned > count {
            if let maxIdx = rangeBlockCounts.indices.max(by: { rangeBlockCounts[$0] < rangeBlockCounts[$1] }) {
                rangeBlockCounts[maxIdx] -= assigned - count
            }
        }

        // Assign blocks to ranges with gap-aware timing
        var blockOffset = indices.lowerBound
        for (rangeIdx, range) in ranges.enumerated() {
            let blocksInRange = rangeBlockCounts[rangeIdx]
            guard blocksInRange > 0 else { continue }

            let rangeIndices = blockOffset..<(blockOffset + blocksInRange)
            let textLengths = rangeIndices.map { max(1.0, Double(blocks[$0].japanese.count)) }
            let totalText = textLengths.reduce(0, +)
            let rangeDuration = range.end - range.start

            // Estimate total needed duration based on text length
            let estimatedDurations = rangeIndices.map { estimateLyricDuration(textLength: blocks[$0].japanese.count) }
            let totalEstimated = estimatedDurations.reduce(0, +)

            if totalEstimated < rangeDuration * 0.85 {
                // Blocks need less time than available — use estimated durations
                // and distribute start positions proportionally within the range
                let spacing = (rangeDuration - totalEstimated) / Double(blocksInRange + 1)
                var cursor = range.start + spacing
                for (j, idx) in rangeIndices.enumerated() {
                    let dur = estimatedDurations[j]
                    blocks[idx].startTime = cursor
                    blocks[idx].endTime = cursor + dur
                    blocks[idx].confidence = confidence
                    cursor += dur + spacing
                }
            } else {
                // Blocks need most/all of the available time — distribute proportionally
                // but still leave small gaps between blocks
                let gapPerBlock = min(0.3, rangeDuration * 0.02)
                let totalGaps = gapPerBlock * Double(max(0, blocksInRange - 1))
                let usableDuration = rangeDuration - totalGaps

                var cursor = range.start
                for (j, idx) in rangeIndices.enumerated() {
                    let proportion = textLengths[j] / totalText
                    let blockDuration = usableDuration * proportion
                    blocks[idx].startTime = cursor
                    blocks[idx].endTime = cursor + blockDuration
                    blocks[idx].confidence = confidence
                    cursor += blockDuration + gapPerBlock
                }
            }

            blockOffset += blocksInRange
        }

        if ranges.count > 1 {
            let gaps = ranges.count - 1
            print("[Alignment] Distributed \(count) blocks across \(ranges.count) vocal ranges (skipped \(gaps) instrumental gap(s))")
        }
    }

    /// Interpolate timing for unmatched blocks using surrounding anchors.
    /// Uses proportional spacing based on text length.
    /// Skips instrumental gaps (regions with no whisper segments) longer than 3s.
    /// Uses vocalOnset as the earliest valid start boundary (not 0:00).
    static func interpolateFromAnchors(_ blocks: inout [LyricBlock], segments: [WhisperSegment], totalDuration: Double, vocalOnset: Double) {
        guard !blocks.isEmpty else { return }

        var i = 0
        while i < blocks.count {
            if blocks[i].startTime != nil {
                i += 1
                continue
            }

            var runEnd = i
            while runEnd < blocks.count && blocks[runEnd].startTime == nil {
                runEnd += 1
            }

            let startBound: Double
            if i > 0, let prevEnd = blocks[i - 1].endTime {
                startBound = prevEnd
            } else {
                startBound = vocalOnset
                print("[Alignment] Interpolating leading blocks from vocal onset \(String(format: "%.2f", vocalOnset))s (not 0:00)")
            }

            let endBound: Double
            if runEnd < blocks.count, let nextStart = blocks[runEnd].startTime {
                endBound = nextStart
            } else {
                endBound = totalDuration
            }

            distributeBlocksIntoVocalRanges(
                blocks: &blocks,
                indices: i..<runEnd,
                segments: segments,
                startBound: startBound,
                endBound: endBound
            )

            i = runEnd
        }
    }
}
