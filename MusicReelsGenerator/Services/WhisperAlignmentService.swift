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

    /// Merge very short consecutive segments into longer ones
    private static func mergeFragments(_ segments: [WhisperSegment], minDuration: Double) -> [WhisperSegment] {
        guard !segments.isEmpty else { return segments }

        var merged: [WhisperSegment] = []
        var current = segments[0]

        for i in 1..<segments.count {
            let next = segments[i]
            let currentDuration = current.endTime - current.startTime

            // Merge if current segment is very short and next is close
            if currentDuration < minDuration && (next.startTime - current.endTime) < 0.5 {
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

    static func align(
        segments: [WhisperSegment],
        to blocks: [LyricBlock],
        mode: AlignmentQualityMode = .balanced,
        onProgress: ((String) -> Void)? = nil
    ) -> [LyricBlock] {
        guard !segments.isEmpty, !blocks.isEmpty else { return blocks }

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

        // === Final: Anchor-based interpolation for remaining unmatched blocks ===
        interpolateFromAnchors(&alignedBlocks, totalDuration: totalDuration, vocalOnset: vocalOnset)

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

                for span in 1...mode.maxCombineSegments {
                    let endSeg = si + span - 1
                    guard endSeg < S else { break }

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
                for span in 1...min(mode.maxCombineSegments, S - si) {
                    let endSeg = si + span - 1
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

    /// Interpolate timing for unmatched blocks using surrounding anchors.
    /// Uses proportional spacing based on text length.
    /// Uses vocalOnset as the earliest valid start boundary (not 0:00).
    private static func interpolateFromAnchors(_ blocks: inout [LyricBlock], totalDuration: Double, vocalOnset: Double) {
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
                // CRITICAL FIX: Use vocal onset, not 0:00.
                // This prevents unmatched early blocks from being pinned to the intro.
                startBound = vocalOnset
                print("[Alignment] Interpolating leading blocks from vocal onset \(String(format: "%.2f", vocalOnset))s (not 0:00)")
            }

            let endBound: Double
            if runEnd < blocks.count, let nextStart = blocks[runEnd].startTime {
                endBound = nextStart
            } else {
                endBound = totalDuration
            }

            let runLength = runEnd - i
            let availableDuration = endBound - startBound

            let textLengths = (i..<runEnd).map { Double(blocks[$0].japanese.count) }
            let totalTextLength = textLengths.reduce(0, +)

            if totalTextLength > 0 && availableDuration > 0 {
                var cursor = startBound
                for j in 0..<runLength {
                    let idx = i + j
                    let proportion = textLengths[j] / totalTextLength
                    let blockDuration = availableDuration * proportion
                    blocks[idx].startTime = cursor
                    blocks[idx].endTime = cursor + blockDuration
                    blocks[idx].confidence = 0.05
                    cursor += blockDuration
                }
            } else {
                let blockDuration = availableDuration / Double(max(runLength, 1))
                for j in 0..<runLength {
                    let idx = i + j
                    blocks[idx].startTime = startBound + Double(j) * blockDuration
                    blocks[idx].endTime = startBound + Double(j + 1) * blockDuration
                    blocks[idx].confidence = 0.05
                }
            }

            i = runEnd
        }
    }

    // MARK: - Debug Report

    private static func printAlignmentReport(_ blocks: [LyricBlock]) {
        print("\n=== ALIGNMENT REPORT ===")
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

            let jaPreview = String(block.japanese.prefix(20))
            print(String(format: "[%2d] %@ conf=%.2f %@ %@", i, flag, conf, timeStr, jaPreview))
        }
        print("=== END REPORT ===\n")
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
