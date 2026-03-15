import Foundation

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum WhisperError: LocalizedError {
    case whisperNotFound
    case modelNotFound(String)
    case transcriptionFailed(String)
    case noSegmentsFound

    var errorDescription: String? {
        switch self {
        case .whisperNotFound:
            return "whisper.cpp not found. Install with: brew install whisper-cpp"
        case .modelNotFound(let path):
            return "Whisper model not found at: \(path). Download a model (e.g., ggml-medium.bin) and place it in the expected location."
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        case .noSegmentsFound:
            return "No speech segments found in audio."
        }
    }
}

struct WhisperSegment {
    let startTime: Double
    let endTime: Double
    let text: String
}

enum WhisperAlignmentService {
    /// Default model search paths (ordered by preference: larger models first)
    static var modelSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/share/whisper-cpp/models/ggml-large-v3-turbo.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-large-v3.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-medium.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-small.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-base.bin",
            "/opt/homebrew/share/whisper-cpp/models/ggml-large-v3-turbo.bin",
            "/opt/homebrew/share/whisper-cpp/models/ggml-large-v3.bin",
            "/opt/homebrew/share/whisper-cpp/models/ggml-medium.bin",
            "/usr/local/share/whisper-cpp/models/ggml-medium.bin",
            "\(home)/whisper-models/ggml-medium.bin"
        ]
    }

    static func findModel() -> String? {
        modelSearchPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Run whisper.cpp transcription and return timestamped segments
    static func transcribe(
        audioURL: URL,
        modelPath: String? = nil,
        language: String = "ja",
        onProgress: ((String) -> Void)? = nil
    ) async throws -> [WhisperSegment] {
        guard let whisper = ProcessRunner.findWhisper() else {
            throw WhisperError.whisperNotFound
        }

        let model: String
        if let mp = modelPath {
            model = mp
        } else if let found = findModel() {
            model = found
        } else {
            throw WhisperError.modelNotFound("(searched default paths)")
        }

        guard FileManager.default.fileExists(atPath: model) else {
            throw WhisperError.modelNotFound(model)
        }

        let modelName = URL(fileURLWithPath: model).lastPathComponent
        onProgress?("Running speech recognition (\(modelName))...")

        // Output CSV format for easy parsing
        let outputBase = NSTemporaryDirectory() + "whisper_output"

        let args = [
            "-m", model,
            "-f", audioURL.path,
            "-l", language,
            "--output-csv",
            "--output-file", outputBase,
            "--no-prints"
        ]

        let result = try await ProcessRunner.run(whisper, arguments: args)

        // Try parsing CSV file first, fall back to stdout
        let csvPath = outputBase + ".csv"
        var segments: [WhisperSegment] = []

        if FileManager.default.fileExists(atPath: csvPath),
           let csvContent = try? String(contentsOfFile: csvPath, encoding: .utf8) {
            segments = parseCSV(csvContent)
            try? FileManager.default.removeItem(atPath: csvPath)
        }

        if segments.isEmpty {
            segments = parseStdout(result.stdout)
        }

        if segments.isEmpty && !result.succeeded {
            throw WhisperError.transcriptionFailed(result.stderr)
        }

        if segments.isEmpty {
            throw WhisperError.noSegmentsFound
        }

        // Merge very short segments that are likely fragments
        segments = mergeFragments(segments, minDuration: 0.3)

        onProgress?("Found \(segments.count) speech segments.")
        return segments
    }

    /// Merge very short consecutive segments into longer ones.
    /// Never merge across non-speech segments (instrumentals/applause).
    private static func mergeFragments(_ segments: [WhisperSegment], minDuration: Double) -> [WhisperSegment] {
        guard !segments.isEmpty else { return segments }

        var merged: [WhisperSegment] = []
        var current = segments[0]

        for i in 1..<segments.count {
            let next = segments[i]
            let currentDuration = current.endTime - current.startTime

            // Never merge speech with non-speech segments
            let currentIsNonSpeech = isNonSpeechSegment(current)
            let nextIsNonSpeech = isNonSpeechSegment(next)

            // Merge if current segment is very short and next is close, and both are same type
            if currentDuration < minDuration && (next.startTime - current.endTime) < 0.5
                && currentIsNonSpeech == nextIsNonSpeech {
                current = WhisperSegment(
                    startTime: current.startTime,
                    endTime: next.endTime,
                    text: current.text + next.text
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    /// Check if a whisper segment is a non-speech marker (applause, music, etc.)
    /// Whisper often produces segments like (拍手), (音楽), [Music], [Applause], etc.
    /// for instrumental/non-vocal sections.
    private static func isNonSpeechSegment(_ segment: WhisperSegment) -> Bool {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Detect markers in parentheses or brackets: (拍手), [Music], etc.
        if (text.hasPrefix("(") && text.hasSuffix(")")) ||
           (text.hasPrefix("[") && text.hasSuffix("]")) ||
           (text.hasPrefix("（") && text.hasSuffix("）")) {
            return true
        }
        // Common non-speech markers
        let nonSpeechPatterns = ["拍手", "音楽", "歓声", "ため息", "笑い", "笑",
                                  "music", "applause", "laughter", "silence"]
        let lower = text.lowercased()
        for pattern in nonSpeechPatterns {
            if lower.contains(pattern.lowercased()) { return true }
        }
        return false
    }

    // MARK: - Multi-Pass Position-Aware Alignment

    /// A candidate match: segment range mapped to a block
    private struct SegmentMatch {
        let segStart: Int
        let segEnd: Int
        let textScore: Double
        let positionScore: Double
        let combinedScore: Double
        var startTime: Double
        var endTime: Double
    }

    /// Align whisper segments to lyric blocks using multi-pass position-aware DP.
    ///
    /// Key improvements over simple beam search:
    /// 1. Position-aware scoring — candidates near expected timeline position score higher
    /// 2. Windowed search — only search segments within a temporal window
    /// 3. Multi-pass refinement — first pass finds anchors, subsequent passes fill gaps
    /// 4. Recovery from bad regions — low-confidence regions are re-aligned locally
    /// Detect the earliest time where vocals/speech likely begin.
    /// Uses the first whisper segment as the vocal onset boundary,
    /// since whisper only produces segments where it detects speech.
    private static func detectVocalOnset(segments: [WhisperSegment]) -> Double {
        guard let first = segments.first else { return 0 }
        // Use a small tolerance before the first segment
        return max(0, first.startTime - 0.5)
    }

    /// Filter out whisper segments that overlap with ignore regions
    static func filterIgnoredSegments(_ segments: [WhisperSegment], ignoreRegions: [IgnoreRegion]) -> [WhisperSegment] {
        guard !ignoreRegions.isEmpty else { return segments }
        return segments.filter { seg in
            !ignoreRegions.contains { $0.overlaps(segmentStart: seg.startTime, segmentEnd: seg.endTime) }
        }
    }

    static func align(
        segments: [WhisperSegment],
        to blocks: [LyricBlock],
        mode: AlignmentQualityMode = .legacy,
        ignoreRegions: [IgnoreRegion] = [],
        onProgress: ((String) -> Void)? = nil
    ) -> [LyricBlock] {
        guard !segments.isEmpty, !blocks.isEmpty else { return blocks }

        // Filter out segments in ignore regions
        let segments = filterIgnoredSegments(segments, ignoreRegions: ignoreRegions)
        if segments.isEmpty { return blocks }
        if !ignoreRegions.isEmpty {
            print("[Alignment] Filtered segments: \(segments.count) remaining after \(ignoreRegions.count) ignore region(s)")
        }

        let B = blocks.count
        let S = segments.count
        let totalDuration = segments.last?.endTime ?? 0
        let vocalOnset = detectVocalOnset(segments: segments)
        onProgress?("Aligning \(S) segments to \(B) lyric blocks (\(mode.rawValue) mode)...")
        print("[Alignment] Detected vocal onset: \(String(format: "%.2f", vocalOnset))s (first segment: \(String(format: "%.2f", segments.first?.startTime ?? 0))s)")

        // === Pass 1: Position-aware DP alignment ===
        var alignedBlocks = positionAwareDP(
            segments: segments,
            blocks: blocks,
            totalDuration: totalDuration,
            vocalOnset: vocalOnset,
            mode: mode,
            onProgress: onProgress
        )

        // === Pass 2+: Refinement passes ===
        for pass in 2...mode.refinementPasses {
            onProgress?("Refinement pass \(pass)/\(mode.refinementPasses)...")
            alignedBlocks = refineAlignment(
                segments: segments,
                blocks: alignedBlocks,
                totalDuration: totalDuration,
                vocalOnset: vocalOnset,
                mode: mode,
                passNumber: pass
            )
        }

        // === Pass 3: Drift detection & local re-anchor ===
        let driftResult = detectAndCorrectDrift(
            blocks: &alignedBlocks,
            segments: segments,
            totalDuration: totalDuration,
            vocalOnset: vocalOnset,
            mode: mode
        )
        if driftResult.driftDetected {
            onProgress?("Drift detected: corrected \(driftResult.correctedCount) blocks")
        }

        // === Final: Anchor-based interpolation for remaining unmatched blocks ===
        interpolateFromAnchors(&alignedBlocks, segments: segments, totalDuration: totalDuration, vocalOnset: vocalOnset)

        // === Post-processing: Cap overly long blocks ===
        // Whisper segments can be very long (20s+) when they span instrumental sections.
        // A matched block shouldn't display longer than its text warrants.
        capOverlongBlocks(&alignedBlocks, segments: segments)

        // === Post-processing: Snap boundaries to segment edges ===
        snapBoundariesToSegments(&alignedBlocks, segments: segments)

        // === Debug: warn if first lyric is suspiciously early ===
        if let firstStart = alignedBlocks.first?.startTime, firstStart < vocalOnset - 1 {
            print("[Alignment] WARNING: First lyric anchor (\(String(format: "%.2f", firstStart))s) is before detected vocal onset (\(String(format: "%.2f", vocalOnset))s)")
        }

        // === Debug summary ===
        let matched = alignedBlocks.filter { ($0.confidence ?? 0) >= mode.matchThreshold }.count
        let highConf = alignedBlocks.filter { ($0.confidence ?? 0) >= 0.6 }.count
        onProgress?("Alignment complete: \(matched)/\(B) matched (\(highConf) high-confidence).")

        printAlignmentReport(alignedBlocks)

        return alignedBlocks
    }

    /// Core position-aware DP alignment
    private static func positionAwareDP(
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
    private static func refineAlignment(
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
    private static func alignRegion(
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
    private static func estimateExpectedTime(
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
    private static func positionScore(
        candidateTime: Double,
        expectedTime: Double,
        windowRadius: Double
    ) -> Double {
        let distance = abs(candidateTime - expectedTime)
        let sigma = windowRadius / 2.5  // ~2.5 sigma covers the window
        return exp(-(distance * distance) / (2 * sigma * sigma))
    }

    // MARK: - Interpolation

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
    private static func interpolateFromAnchors(_ blocks: inout [LyricBlock], segments: [WhisperSegment], totalDuration: Double, vocalOnset: Double) {
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

    // MARK: - Public Region Re-Alignment

    /// Re-align a bounded region of blocks using cached whisper segments.
    /// Only modifies blocks within the given range that are not anchored/manually adjusted.
    /// Anchored blocks serve as hard timing constraints.
    ///
    /// - Parameters:
    ///   - segments: Full set of whisper segments from transcription
    ///   - allBlocks: All lyric blocks (only the target range will be modified)
    ///   - fromIndex: Start of target range (inclusive)
    ///   - toIndex: End of target range (inclusive)
    ///   - timeBefore: Hard left time boundary (from preceding anchor or 0)
    ///   - timeAfter: Hard right time boundary (from following anchor or duration)
    ///   - mode: Alignment quality mode
    /// - Returns: Updated copy of allBlocks with only the target range re-aligned
    static func realignRegion(
        segments: [WhisperSegment],
        allBlocks: [LyricBlock],
        fromIndex: Int,
        toIndex: Int,
        timeBefore: Double,
        timeAfter: Double,
        mode: AlignmentQualityMode = .legacy,
        ignoreRegions: [IgnoreRegion] = []
    ) -> [LyricBlock] {
        guard fromIndex >= 0, toIndex < allBlocks.count, fromIndex <= toIndex else {
            return allBlocks
        }

        // Filter segments to the time range, excluding ignore regions
        let filteredSegments = filterIgnoredSegments(segments, ignoreRegions: ignoreRegions)
        let regionSegments = filteredSegments.filter { seg in
            seg.startTime >= timeBefore - 1 && seg.endTime <= timeAfter + 1
        }

        guard !regionSegments.isEmpty else {
            print("[LocalRealign] No segments found in time range \(String(format: "%.1f", timeBefore))–\(String(format: "%.1f", timeAfter))s")
            return allBlocks
        }

        let regionBlocks = Array(allBlocks[fromIndex...toIndex])
        let regionDuration = timeAfter - timeBefore

        print("[LocalRealign] Re-aligning blocks \(fromIndex)–\(toIndex) in time range \(String(format: "%.1f", timeBefore))–\(String(format: "%.1f", timeAfter))s (\(regionSegments.count) segments)")

        let localAligned = alignRegion(
            segments: regionSegments,
            blocks: regionBlocks,
            regionStart: timeBefore,
            regionEnd: timeAfter,
            regionDuration: regionDuration,
            mode: mode
        )

        // Merge results back — only update non-anchored blocks
        var result = allBlocks
        for j in 0..<localAligned.count {
            let globalIdx = fromIndex + j
            // Never overwrite anchored or manually adjusted blocks
            if result[globalIdx].isAnchor || result[globalIdx].isManuallyAdjusted {
                continue
            }
            // Only apply if we got a result (non-nil timing)
            if localAligned[j].startTime != nil {
                result[globalIdx].startTime = localAligned[j].startTime
                result[globalIdx].endTime = localAligned[j].endTime
                result[globalIdx].confidence = localAligned[j].confidence
                result[globalIdx].isAnchor = localAligned[j].isAnchor
            }
        }

        // Validate: ensure no backward time jumps across the whole result
        for i in 1..<result.count {
            if let prevStart = result[i - 1].startTime,
               let curStart = result[i].startTime,
               curStart < prevStart {
                // Fix by pushing current forward
                result[i].startTime = prevStart + 0.05
                if let curEnd = result[i].endTime, curEnd <= result[i].startTime! {
                    result[i].endTime = result[i].startTime! + 0.1
                }
            }
        }

        // Log changes
        var changed = 0
        for j in 0..<localAligned.count {
            let globalIdx = fromIndex + j
            if result[globalIdx].startTime != allBlocks[globalIdx].startTime {
                changed += 1
            }
        }
        print("[LocalRealign] Changed \(changed)/\(localAligned.count) blocks in region")

        return result
    }

    // MARK: - Drift Detection & Correction

    private struct DriftResult {
        let driftDetected: Bool
        let correctedCount: Int
    }

    /// Detect systematic timing drift in aligned blocks and attempt local re-anchor.
    ///
    /// Drift occurs when a run of blocks all shifted in the same direction relative
    /// to their expected positions (e.g., chorus confusion pulling blocks early/late).
    /// We detect this by checking if consecutive low-confidence blocks have consistent
    /// offset from expected position, then re-align the suspicious region.
    private static func detectAndCorrectDrift(
        blocks: inout [LyricBlock],
        segments: [WhisperSegment],
        totalDuration: Double,
        vocalOnset: Double,
        mode: AlignmentQualityMode
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

                    let localAligned = alignRegion(
                        segments: regionSegments,
                        blocks: regionBlocks,
                        regionStart: timeBefore,
                        regionEnd: timeAfter,
                        regionDuration: regionDuration,
                        mode: mode
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

    // MARK: - Boundary Snap

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
    private static func capOverlongBlocks(
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
    private static func snapBoundariesToSegments(
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

    // MARK: - Debug Report

    private static func printAlignmentReport(_ blocks: [LyricBlock]) {
        print("\n=== ALIGNMENT REPORT ===")
        var gapCount = 0
        var totalGapDuration = 0.0
        for (i, block) in blocks.enumerated() {
            let conf = block.confidence ?? 0
            let flag: String
            if block.isManuallyAdjusted { flag = "MANUAL" }
            else if block.isAnchor { flag = "ANCHOR" }
            else if conf < 0.1 { flag = "INTERP" }
            else if conf < 0.4 { flag = "  WEAK" }
            else { flag = "    OK" }

            let timeStr: String
            if let s = block.startTime, let e = block.endTime {
                timeStr = String(format: "%6.2f–%6.2f", s, e)
            } else {
                timeStr = "   -.--–   -.--"
            }

            // Detect gap from previous block
            if i > 0, let prevEnd = blocks[i - 1].endTime, let curStart = block.startTime {
                let gap = curStart - prevEnd
                if gap > 0.5 {
                    gapCount += 1
                    totalGapDuration += gap
                    print(String(format: "     ⏸ GAP %.2fs (no subtitle)", gap))
                }
            }

            let jaPreview = String(block.japanese.prefix(20))
            print(String(format: "[%2d] %@ conf=%.2f %@ %@", i, flag, conf, timeStr, jaPreview))
        }
        if gapCount > 0 {
            print(String(format: "[Alignment] %d gap(s) detected (total %.1fs of no-subtitle time)", gapCount, totalGapDuration))
        }
        print("=== END REPORT ===\n")

        // Also write report to a file for debugging
        var reportLines: [String] = ["=== ALIGNMENT REPORT ==="]
        for (i, block) in blocks.enumerated() {
            let conf = block.confidence ?? 0
            let flag: String
            if block.isManuallyAdjusted { flag = "MANUAL" }
            else if block.isAnchor { flag = "ANCHOR" }
            else if conf < 0.1 { flag = "INTERP" }
            else if conf < 0.4 { flag = "  WEAK" }
            else { flag = "    OK" }
            let timeStr: String
            if let s = block.startTime, let e = block.endTime {
                timeStr = String(format: "%6.2f–%6.2f (dur=%.2f)", s, e, e - s)
            } else {
                timeStr = "   -.--–   -.-- (no timing)"
            }
            if i > 0, let prevEnd = blocks[i - 1].endTime, let curStart = block.startTime {
                let gap = curStart - prevEnd
                if gap > 0.5 {
                    reportLines.append(String(format: "     ⏸ GAP %.2fs (no subtitle)", gap))
                } else if gap < -0.01 {
                    reportLines.append(String(format: "     ⚠ OVERLAP %.2fs", -gap))
                }
            }
            let jaPreview = String(block.japanese.prefix(30))
            reportLines.append(String(format: "[%2d] %@ conf=%.2f %@ %@", i, flag, conf, timeStr, jaPreview))
        }
        reportLines.append("=== END REPORT ===")
        let reportText = reportLines.joined(separator: "\n")
        try? reportText.write(toFile: "/tmp/mreels_alignment_report.txt", atomically: true, encoding: .utf8)
    }

    // MARK: - Parsing

    private static func parseCSV(_ csv: String) -> [WhisperSegment] {
        let lines = csv.components(separatedBy: .newlines)
        var segments: [WhisperSegment] = []

        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3 else { continue }

            guard let start = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let end = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }

            let text = parts.dropFirst(2).joined(separator: ",")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            if !text.isEmpty {
                // whisper-cpp CSV times are in milliseconds
                segments.append(WhisperSegment(
                    startTime: start / 1000.0,
                    endTime: end / 1000.0,
                    text: text
                ))
            }
        }
        return segments
    }

    private static func parseStdout(_ output: String) -> [WhisperSegment] {
        let pattern = #"\[(\d{2}:\d{2}:\d{2}\.\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}\.\d{3})\]\s*(.*)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let lines = output.components(separatedBy: .newlines)
        var segments: [WhisperSegment] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex?.firstMatch(in: line, range: range) {
                if let startRange = Range(match.range(at: 1), in: line),
                   let endRange = Range(match.range(at: 2), in: line),
                   let textRange = Range(match.range(at: 3), in: line) {
                    let startStr = String(line[startRange])
                    let endStr = String(line[endRange])
                    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)

                    if let start = parseTimestamp(startStr),
                       let end = parseTimestamp(endStr),
                       !text.isEmpty {
                        segments.append(WhisperSegment(
                            startTime: start,
                            endTime: end,
                            text: text
                        ))
                    }
                }
            }
        }
        return segments
    }

    private static func parseTimestamp(_ str: String) -> Double? {
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard secParts.count == 2,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(secParts[0]),
              let millis = Double(secParts[1]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds + millis / 1000.0
    }
}
