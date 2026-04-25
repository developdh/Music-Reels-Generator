import Foundation

extension WhisperAlignmentService {
    /// Snap block boundaries to nearest whisper segment edges.
    /// Tighten block timing so each lyric line only displays for a reasonable duration.
    ///
    /// Problem: Whisper sentence-level segments can be very long (20s+) when they
    /// span across instrumental sections. A block matched to such a segment gets
    /// startTime/endTime covering the full segment, making the lyric visible during
    /// the instrumental gap.
    ///
    /// Strategy: For each contiguous run of blocks, estimate per-block display
    /// durations from text length, then assign each block a tight time window
    /// within its original allocation — preserving gaps where singing stops.
    static func capOverlongBlocks(
        _ blocks: inout [LyricBlock],
        segments: [WhisperSegment]
    ) {
        guard !blocks.isEmpty else { return }

        // Process each block individually
        for i in 0..<blocks.count {
            guard !blocks[i].isManuallyAdjusted else { continue }
            guard let start = blocks[i].startTime, let end = blocks[i].endTime else { continue }

            let duration = end - start
            let textLen = blocks[i].japanese.count

            // Estimate reasonable display time: ~3.5 chars/sec + 1.5s buffer, min 2.5s
            let estimatedDuration = max(2.5, Double(textLen) / 3.5 + 1.5)

            // Only process if block is significantly longer than needed
            guard duration > estimatedDuration * 1.3 else { continue }

            // Determine where within this block's time range the singing likely happens.
            // Look at the next block's start to figure out the structure.
            let nextStart = (i + 1 < blocks.count) ? blocks[i + 1].startTime : nil

            // Determine the singing position within this time range:
            // The lyric is probably sung near the START of its time range
            // (the tail is usually the instrumental gap before the next lyric).
            var newEnd = start + estimatedDuration

            // Use whisper segments to refine: find where speech actually ends
            // within this block's time range
            let overlapping = segments.filter { seg in
                seg.endTime > start && seg.startTime < end
            }

            if overlapping.count >= 2 {
                // Multiple segments within this block's range — find where a gap occurs
                // after the singing part that matches this lyric
                var speechEnd = overlapping[0].endTime
                for seg in overlapping.dropFirst() {
                    if seg.startTime - speechEnd > 2.0 {
                        // Found a gap > 2s — singing likely stopped at speechEnd
                        break
                    }
                    speechEnd = seg.endTime
                }
                // Use the speech-end if it gives a reasonable duration
                let speechDuration = speechEnd - start
                if speechDuration >= 2.0 && speechDuration < duration * 0.8 {
                    newEnd = speechEnd
                }
            }

            // Don't overlap with next block
            if let ns = nextStart, newEnd > ns {
                newEnd = ns
            }

            // Only apply if we're meaningfully shortening
            if newEnd < end - 0.5 && newEnd > start + 1.0 {
                print(String(format: "[CapOverlong] Block %d: %.2f–%.2f (%.1fs) → %.2f–%.2f (%.1fs) [%d chars]",
                             i, start, end, duration, start, newEnd, newEnd - start, textLen))
                blocks[i].endTime = newEnd
            }
        }
    }

    /// This is a safe post-processing step that aligns start/end times
    /// to actual speech onset/offset detected by whisper, improving
    /// subtitle timing without changing which segment was matched.
    static func snapBoundariesToSegments(
        _ blocks: inout [LyricBlock],
        segments: [WhisperSegment],
        snapThreshold: Double = 0.3
    ) {
        guard !segments.isEmpty else { return }

        // Build sorted arrays of segment start and end times for binary search
        let segStarts = segments.map(\.startTime).sorted()
        let segEnds = segments.map(\.endTime).sorted()

        for i in 0..<blocks.count {
            guard !blocks[i].isManuallyAdjusted else { continue }
            guard blocks[i].startTime != nil else { continue }

            // Snap start time to nearest segment start
            if let start = blocks[i].startTime,
               let nearest = findNearest(in: segStarts, to: start) {
                let delta = abs(nearest - start)
                if delta > 0.01 && delta <= snapThreshold {
                    blocks[i].startTime = nearest
                }
            }

            // Snap end time to nearest segment end
            if let end = blocks[i].endTime,
               let nearest = findNearest(in: segEnds, to: end) {
                let delta = abs(nearest - end)
                if delta > 0.01 && delta <= snapThreshold {
                    blocks[i].endTime = nearest
                }
            }

            // Ensure start < end after snapping
            if let s = blocks[i].startTime, let e = blocks[i].endTime, s >= e {
                blocks[i].endTime = s + 0.1
            }
        }
    }

    /// Find the nearest value in a sorted array using binary search.
    private static func findNearest(in sorted: [Double], to target: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }

        var lo = 0, hi = sorted.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // Check lo and lo-1 for the closest
        var best = sorted[lo]
        if lo > 0 && abs(sorted[lo - 1] - target) < abs(best - target) {
            best = sorted[lo - 1]
        }
        return best
    }
}
