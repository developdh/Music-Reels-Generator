import Foundation

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension WhisperAlignmentService {
    /// A candidate match: segment range mapped to a block
    fileprivate struct SegmentMatch {
        let segStart: Int
        let segEnd: Int
        let textScore: Double
        let positionScore: Double
        let combinedScore: Double
        var startTime: Double
        var endTime: Double
    }

    /// Core position-aware DP alignment
    static func positionAwareDP(
        segments: [WhisperSegment],
        blocks: [LyricBlock],
        totalDuration: Double,
        vocalOnset: Double,
        mode: AlignmentQualityMode,
        onProgress: ((String) -> Void)?
    ) -> [LyricBlock] {
        let B = blocks.count
        let S = segments.count

        // Step 1: Build windowed, position-scored candidates for each block
        var candidates: [[SegmentMatch]] = Array(repeating: [], count: B)

        for bi in 0..<B {
            if blocks[bi].isManuallyAdjusted { continue }

            let blockText = blocks[bi].japanese
            let expectedTime = estimateExpectedTime(
                blockIndex: bi, totalBlocks: B, totalDuration: totalDuration,
                vocalOnset: vocalOnset,
                existingBlocks: blocks
            )

            // Windowed search: only check segments near the expected position
            let windowStart = max(0, expectedTime - mode.searchWindowSeconds)
            let windowEnd = min(totalDuration, expectedTime + mode.searchWindowSeconds)

            for si in 0..<S {
                let segTime = segments[si].startTime

                // Skip segments outside the search window
                if segTime < windowStart - 5 || segTime > windowEnd + 5 { continue }

                // Skip non-speech segments as starting point for matching
                if isNonSpeechSegment(segments[si]) { continue }

                for span in 1...mode.maxCombineSegments {
                    let endSeg = si + span - 1
                    guard endSeg < S else { break }

                    // Don't combine across non-speech segments (instrumentals)
                    if span > 1 && isNonSpeechSegment(segments[endSeg]) { break }

                    // Skip combinations that start by including a non-speech segment before si
                    let combinedText = (si...endSeg).map { segments[$0].text }.joined()
                    let textScore = JapaneseTextNormalizer.similarity(blockText, combinedText)

                    if textScore >= mode.matchThreshold {
                        let segMidTime = (segments[si].startTime + segments[endSeg].endTime) / 2.0
                        let posScore = positionScore(
                            candidateTime: segMidTime,
                            expectedTime: expectedTime,
                            windowRadius: mode.searchWindowSeconds
                        )

                        let combined = textScore * (1.0 - mode.positionWeight) + posScore * mode.positionWeight

                        candidates[bi].append(SegmentMatch(
                            segStart: si,
                            segEnd: endSeg,
                            textScore: textScore,
                            positionScore: posScore,
                            combinedScore: combined,
                            startTime: segments[si].startTime,
                            endTime: segments[endSeg].endTime
                        ))
                    }
                }
            }

            // Sort candidates by combined score descending, keep top to limit search
            candidates[bi].sort { $0.combinedScore > $1.combinedScore }
            let maxCandidates = mode.beamWidth * 2
            if candidates[bi].count > maxCandidates {
                candidates[bi] = Array(candidates[bi].prefix(maxCandidates))
            }
        }

        // Step 2: Monotonic DP with beam search
        struct DPState {
            var totalScore: Double
            var lastSegEnd: Int
            var lastMatchTime: Double  // time of last matched segment end
            var choices: [Int?]        // index into candidates[bi] or nil
        }

        var beam: [DPState] = [DPState(totalScore: 0, lastSegEnd: -1, lastMatchTime: 0, choices: [])]

        for bi in 0..<B {
            if bi % 5 == 0 {
                onProgress?("Aligning block \(bi + 1)/\(B)...")
            }

            var nextBeam: [DPState] = []

            for state in beam {
                // Option 1: Skip this block
                var skipped = state
                skipped.choices.append(nil)
                nextBeam.append(skipped)

                // Option 2: Match with a candidate
                if !blocks[bi].isManuallyAdjusted {
                    for (ci, cand) in candidates[bi].enumerated() {
                        // Monotonic constraint: segment must come after last matched segment
                        guard cand.segStart > state.lastSegEnd else { continue }

                        // Temporal continuity bonus: reward candidates that maintain
                        // reasonable time gaps from the last match
                        var continuityBonus: Double = 0
                        if state.lastMatchTime > 0 {
                            let gap = cand.startTime - state.lastMatchTime
                            // Penalize very large gaps (likely skipped too much)
                            // and negative gaps (shouldn't happen due to monotonic constraint)
                            if gap >= 0 && gap < 30 {
                                continuityBonus = 0.05 * (1.0 - gap / 30.0)
                            }
                        }

                        var matched = state
                        matched.totalScore += cand.combinedScore + continuityBonus
                        matched.lastSegEnd = cand.segEnd
                        matched.lastMatchTime = cand.endTime
                        matched.choices.append(ci)
                        nextBeam.append(matched)
                    }
                }
            }

            // Prune beam
            nextBeam.sort { $0.totalScore > $1.totalScore }
            beam = Array(nextBeam.prefix(mode.beamWidth))
        }

        // Pick best final state
        guard let best = beam.first else { return blocks }

        // Step 3: Apply results
        var alignedBlocks = blocks
        for bi in 0..<B {
            guard !alignedBlocks[bi].isManuallyAdjusted else {
                alignedBlocks[bi].isAnchor = true
                continue
            }

            if let ci = best.choices[bi], let cand = candidates[bi][safe: ci] {
                alignedBlocks[bi].startTime = cand.startTime
                alignedBlocks[bi].endTime = cand.endTime
                alignedBlocks[bi].confidence = cand.textScore
                alignedBlocks[bi].isAnchor = cand.textScore >= 0.6
            } else {
                alignedBlocks[bi].startTime = nil
                alignedBlocks[bi].endTime = nil
                alignedBlocks[bi].confidence = 0
                alignedBlocks[bi].isAnchor = false
            }
        }

        return alignedBlocks
    }

    /// Refine alignment by re-aligning low-confidence regions between anchors
    static func refineAlignment(
        segments: [WhisperSegment],
        blocks: [LyricBlock],
        totalDuration: Double,
        vocalOnset: Double,
        mode: AlignmentQualityMode,
        passNumber: Int
    ) -> [LyricBlock] {
        var refined = blocks

        // Find runs of low-confidence blocks between anchors
        var i = 0
        while i < refined.count {
            let block = refined[i]
            let isAnchor = block.isAnchor || block.isManuallyAdjusted
            let isHighConf = (block.confidence ?? 0) >= 0.5

            if isAnchor || isHighConf {
                i += 1
                continue
            }

            // Found a weak block — find the extent of the weak region
            var regionEnd = i + 1
            while regionEnd < refined.count {
                let b = refined[regionEnd]
                if b.isAnchor || b.isManuallyAdjusted || (b.confidence ?? 0) >= 0.5 {
                    break
                }
                regionEnd += 1
            }

            let regionLength = regionEnd - i
            if regionLength == 0 {
                i += 1
                continue
            }

            // Determine time bounds from surrounding anchors/high-confidence blocks
            let timeBefore: Double
            if i > 0, let end = refined[i - 1].endTime {
                timeBefore = end
            } else {
                // Use vocal onset as the earliest valid boundary
                timeBefore = vocalOnset
            }

            let timeAfter: Double
            if regionEnd < refined.count, let start = refined[regionEnd].startTime {
                timeAfter = start
            } else {
                timeAfter = totalDuration
            }

            // Find segments in this time range
            let regionSegments = segments.filter { seg in
                seg.startTime >= timeBefore - 1 && seg.endTime <= timeAfter + 1
            }

            if !regionSegments.isEmpty {
                // Re-align just this region with tighter constraints
                let regionBlocks = Array(refined[i..<regionEnd])
                let regionDuration = timeAfter - timeBefore

                let localAligned = alignRegion(
                    segments: regionSegments,
                    blocks: regionBlocks,
                    regionStart: timeBefore,
                    regionEnd: timeAfter,
                    regionDuration: regionDuration,
                    mode: mode
                )

                // Apply local results
                for j in 0..<regionLength {
                    let localBlock = localAligned[j]
                    if localBlock.startTime != nil && (localBlock.confidence ?? 0) > (refined[i + j].confidence ?? 0) {
                        refined[i + j] = localBlock
                    }
                }
            }

            i = regionEnd
        }

        return refined
    }

    /// Align a small region of blocks to nearby segments
    static func alignRegion(
        segments: [WhisperSegment],
        blocks: [LyricBlock],
        regionStart: Double,
        regionEnd: Double,
        regionDuration: Double,
        mode: AlignmentQualityMode
    ) -> [LyricBlock] {
        let B = blocks.count
        let S = segments.count
        guard B > 0, S > 0 else { return blocks }

        let matchThreshold = max(mode.matchThreshold - 0.05, 0.15)

        // Build candidates — search all segments in region (it's already filtered)
        var candidates: [[SegmentMatch]] = Array(repeating: [], count: B)

        for bi in 0..<B {
            if blocks[bi].isManuallyAdjusted { continue }

            let blockText = blocks[bi].japanese
            let expectedTime = regionStart + (Double(bi) + 0.5) / Double(B) * regionDuration

            for si in 0..<S {
                // Skip non-speech segments as starting point
                if isNonSpeechSegment(segments[si]) { continue }

                for span in 1...min(mode.maxCombineSegments, S - si) {
                    let endSeg = si + span - 1
                    if span > 1 && isNonSpeechSegment(segments[endSeg]) { break }

                    let combinedText = (si...endSeg).map { segments[$0].text }.joined()
                    let textScore = JapaneseTextNormalizer.similarity(blockText, combinedText)

                    if textScore >= matchThreshold {
                        let segMidTime = (segments[si].startTime + segments[endSeg].endTime) / 2.0
                        let posScore = positionScore(
                            candidateTime: segMidTime,
                            expectedTime: expectedTime,
                            windowRadius: regionDuration / 2
                        )

                        let combined = textScore * 0.65 + posScore * 0.35

                        candidates[bi].append(SegmentMatch(
                            segStart: si, segEnd: endSeg,
                            textScore: textScore, positionScore: posScore,
                            combinedScore: combined,
                            startTime: segments[si].startTime,
                            endTime: segments[endSeg].endTime
                        ))
                    }
                }
            }

            candidates[bi].sort { $0.combinedScore > $1.combinedScore }
            if candidates[bi].count > 50 {
                candidates[bi] = Array(candidates[bi].prefix(50))
            }
        }

        // Simple DP for the small region
        struct DPState {
            var totalScore: Double
            var lastSegEnd: Int
            var choices: [Int?]
        }

        var beam: [DPState] = [DPState(totalScore: 0, lastSegEnd: -1, choices: [])]
        let beamWidth = min(mode.beamWidth, 100)

        for bi in 0..<B {
            var nextBeam: [DPState] = []
            for state in beam {
                var skipped = state
                skipped.choices.append(nil)
                nextBeam.append(skipped)

                if !blocks[bi].isManuallyAdjusted {
                    for (ci, cand) in candidates[bi].enumerated() {
                        guard cand.segStart > state.lastSegEnd else { continue }
                        var matched = state
                        matched.totalScore += cand.combinedScore
                        matched.lastSegEnd = cand.segEnd
                        matched.choices.append(ci)
                        nextBeam.append(matched)
                    }
                }
            }
            nextBeam.sort { $0.totalScore > $1.totalScore }
            beam = Array(nextBeam.prefix(beamWidth))
        }

        guard let best = beam.first else { return blocks }

        var result = blocks
        for bi in 0..<B {
            guard !result[bi].isManuallyAdjusted else { continue }
            if let ci = best.choices[bi], let cand = candidates[bi][safe: ci] {
                result[bi].startTime = cand.startTime
                result[bi].endTime = cand.endTime
                result[bi].confidence = cand.textScore
                result[bi].isAnchor = cand.textScore >= 0.6
            }
        }

        return result
    }

    // MARK: - Position Scoring

    /// Estimate where a block is expected to appear in the timeline.
    /// Uses existing anchor/manual blocks as reference points when available.
    /// Distributes blocks from vocalOnset to totalDuration, NOT from 0.
    static func estimateExpectedTime(
        blockIndex: Int, totalBlocks: Int, totalDuration: Double,
        vocalOnset: Double,
        existingBlocks: [LyricBlock]
    ) -> Double {
        // Try to find the nearest anchors before and after
        var prevAnchorIdx: Int? = nil
        var prevAnchorTime: Double? = nil
        var nextAnchorIdx: Int? = nil
        var nextAnchorTime: Double? = nil

        for i in stride(from: blockIndex - 1, through: 0, by: -1) {
            if existingBlocks[i].isManuallyAdjusted || existingBlocks[i].isAnchor,
               let st = existingBlocks[i].startTime {
                prevAnchorIdx = i
                prevAnchorTime = st
                break
            }
        }

        for i in (blockIndex + 1)..<totalBlocks {
            if existingBlocks[i].isManuallyAdjusted || existingBlocks[i].isAnchor,
               let st = existingBlocks[i].startTime {
                nextAnchorIdx = i
                nextAnchorTime = st
                break
            }
        }

        // Interpolate between anchors if both exist
        if let pIdx = prevAnchorIdx, let pTime = prevAnchorTime,
           let nIdx = nextAnchorIdx, let nTime = nextAnchorTime {
            let fraction = Double(blockIndex - pIdx) / Double(nIdx - pIdx)
            return pTime + fraction * (nTime - pTime)
        }

        // Use one anchor + proportional estimate
        if let pIdx = prevAnchorIdx, let pTime = prevAnchorTime {
            let blocksRemaining = totalBlocks - pIdx
            let timeRemaining = totalDuration - pTime
            let fraction = Double(blockIndex - pIdx) / Double(blocksRemaining)
            return pTime + fraction * timeRemaining
        }

        if let nIdx = nextAnchorIdx, let nTime = nextAnchorTime {
            let fraction = Double(blockIndex) / Double(nIdx)
            return vocalOnset + fraction * (nTime - vocalOnset)
        }

        // Default: linear distribution from vocal onset to total duration
        // This is the critical fix — blocks are expected between vocalOnset and end,
        // NOT from 0:00. This prevents intro regions from attracting lyrics.
        let lyricDuration = totalDuration - vocalOnset
        return vocalOnset + (Double(blockIndex) + 0.5) / Double(totalBlocks) * lyricDuration
    }

    /// Score how plausible a candidate's position is relative to expected position.
    /// Returns 0.0 to 1.0 using Gaussian falloff.
    fileprivate static func positionScore(
        candidateTime: Double,
        expectedTime: Double,
        windowRadius: Double
    ) -> Double {
        let distance = abs(candidateTime - expectedTime)
        let sigma = windowRadius / 2.5  // ~2.5 sigma covers the window
        return exp(-(distance * distance) / (2 * sigma * sigma))
    }
}
