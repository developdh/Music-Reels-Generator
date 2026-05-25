import Foundation

extension WhisperAlignmentService {
    fileprivate struct DriftResult {
        let driftDetected: Bool
        let correctedCount: Int
    }

    /// Detect systematic timing drift in aligned blocks and attempt local re-anchor.
    ///
    /// Drift occurs when a run of blocks all shifted in the same direction relative
    /// to their expected positions (e.g., chorus confusion pulling blocks early/late).
    /// We detect this by checking if consecutive low-confidence blocks have consistent
    /// offset from expected position, then re-align the suspicious region.
    static func detectAndCorrectDrift(
        blocks: inout [LyricBlock],
        segments: [WhisperSegment],
        totalDuration: Double,
        vocalOnset: Double,
        mode: AlignmentQualityMode,
        repetitionCounts: [Int]
    ) -> (driftDetected: Bool, correctedCount: Int) {
        let result = detectAndCorrectDriftImpl(
            blocks: &blocks,
            segments: segments,
            totalDuration: totalDuration,
            vocalOnset: vocalOnset,
            mode: mode,
            repetitionCounts: repetitionCounts
        )
        return (result.driftDetected, result.correctedCount)
    }

    private static func detectAndCorrectDriftImpl(
        blocks: inout [LyricBlock],
        segments: [WhisperSegment],
        totalDuration: Double,
        vocalOnset: Double,
        mode: AlignmentQualityMode,
        repetitionCounts: [Int]
    ) -> DriftResult {
        let B = blocks.count
        guard B >= 4 else { return DriftResult(driftDetected: false, correctedCount: 0) }

        var correctedCount = 0

        // Scan for runs of weak blocks that might be drifted
        var i = 0
        while i < B {
            let block = blocks[i]
            // Skip anchors and manually adjusted blocks
            if block.isAnchor || block.isManuallyAdjusted || (block.confidence ?? 0) >= 0.5 {
                i += 1
                continue
            }

            // Find extent of weak region
            var regionEnd = i + 1
            while regionEnd < B {
                let b = blocks[regionEnd]
                if b.isAnchor || b.isManuallyAdjusted || (b.confidence ?? 0) >= 0.5 {
                    break
                }
                regionEnd += 1
            }

            let regionLength = regionEnd - i

            // Only investigate regions of 3+ consecutive weak blocks
            if regionLength >= 3, let driftDirection = detectDriftDirection(
                blocks: blocks, range: i..<regionEnd,
                totalBlocks: B, totalDuration: totalDuration, vocalOnset: vocalOnset
            ) {
                print("[Alignment] Drift detected in blocks \(i)–\(regionEnd - 1): \(String(format: "%.1f", driftDirection))s systematic shift")

                // Re-anchor: determine correct time bounds from surrounding anchors
                let timeBefore: Double
                if i > 0, let end = blocks[i - 1].endTime {
                    timeBefore = end
                } else {
                    timeBefore = vocalOnset
                }

                let timeAfter: Double
                if regionEnd < B, let start = blocks[regionEnd].startTime {
                    timeAfter = start
                } else {
                    timeAfter = totalDuration
                }

                // Find segments in the corrected time range
                let regionSegments = segments.filter { seg in
                    seg.startTime >= timeBefore - 1 && seg.endTime <= timeAfter + 1
                }

                if !regionSegments.isEmpty {
                    let regionBlocks = Array(blocks[i..<regionEnd])
                    let regionDuration = timeAfter - timeBefore
                    let regionRepetitions = Array(repetitionCounts[i..<regionEnd])

                    let localAligned = alignRegion(
                        segments: regionSegments,
                        blocks: regionBlocks,
                        regionStart: timeBefore,
                        regionEnd: timeAfter,
                        regionDuration: regionDuration,
                        mode: mode,
                        repetitionCounts: regionRepetitions
                    )

                    // Apply only if improvement
                    for j in 0..<regionLength {
                        let localBlock = localAligned[j]
                        let oldConf = blocks[i + j].confidence ?? 0
                        let newConf = localBlock.confidence ?? 0
                        if localBlock.startTime != nil && newConf > oldConf {
                            blocks[i + j] = localBlock
                            correctedCount += 1
                        }
                    }
                }
            }

            i = regionEnd
        }

        return DriftResult(driftDetected: correctedCount > 0, correctedCount: correctedCount)
    }

    /// Check if a run of blocks has systematic drift (all shifted in same direction).
    /// Returns the average drift in seconds, or nil if no consistent drift detected.
    private static func detectDriftDirection(
        blocks: [LyricBlock],
        range: Range<Int>,
        totalBlocks: Int,
        totalDuration: Double,
        vocalOnset: Double
    ) -> Double? {
        var drifts: [Double] = []

        for i in range {
            guard let startTime = blocks[i].startTime else { continue }

            let expected = estimateExpectedTime(
                blockIndex: i, totalBlocks: totalBlocks, totalDuration: totalDuration,
                vocalOnset: vocalOnset, existingBlocks: blocks
            )
            drifts.append(startTime - expected)
        }

        guard drifts.count >= 2 else { return nil }

        let meanDrift = drifts.reduce(0, +) / Double(drifts.count)

        // Check if drift is consistent (all in same direction, magnitude > 2s)
        let allSameDirection = drifts.allSatisfy { ($0 > 0) == (meanDrift > 0) }
        let significantDrift = abs(meanDrift) > 2.0

        if allSameDirection && significantDrift {
            return meanDrift
        }
        return nil
    }
}
