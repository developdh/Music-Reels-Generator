import Foundation

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
    /// Average non-special token probability from whisper. nil when parsed from
    /// a source that doesn't expose token confidence (stdout regex fallback, etc.)
    let confidence: Double?

    init(startTime: Double, endTime: Double, text: String, confidence: Double? = nil) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.confidence = confidence
    }
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
        language: String? = "ja",
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

        // Use full JSON output: includes per-token probabilities so we can
        // derive per-segment confidence and down-weight hallucinated transcripts.
        let outputBase = NSTemporaryDirectory() + "whisper_output"

        var args = [
            "-m", model,
            "-f", audioURL.path,
            "--output-json-full",
            "--output-file", outputBase,
            "--no-prints"
        ]
        if let language {
            args.insert(contentsOf: ["-l", language], at: 4)
        }

        let result = try await ProcessRunner.run(whisper, arguments: args)

        // Try parsing JSON file first (with confidence), fall back to stdout regex.
        let jsonPath = outputBase + ".json"
        var segments: [WhisperSegment] = []

        if FileManager.default.fileExists(atPath: jsonPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)) {
            segments = parseJSON(data)
            try? FileManager.default.removeItem(atPath: jsonPath)
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

    /// Per-block text repetition counts (normalized exact match). Used to choose
    /// adaptive position-vs-text weighting: unique lines trust text, chorus
    /// lines trust position to prevent drift between repeated instances.
    static func repetitionCounts(_ blocks: [LyricBlock]) -> [Int] {
        let normalized = blocks.map { JapaneseTextNormalizer.normalize($0.japanese) }
        var counts: [String: Int] = [:]
        for t in normalized { counts[t, default: 0] += 1 }
        return normalized.map { counts[$0] ?? 1 }
    }

    /// Pre-anchor unique (non-repeated) lyric blocks via greedy monotonic
    /// text-best match. Choruses are ambiguous but verses/bridges aren't —
    /// anchoring uniques first gives the subsequent DP reliable time references,
    /// so chorus blocks land on the correct repetition instance.
    /// Requires high text score and minimum length to avoid false anchors.
    static func greedyAnchorUniqueBlocks(
        segments: [WhisperSegment],
        blocks: [LyricBlock],
        repetitions: [Int],
        mode: AlignmentQualityMode,
        minTextLength: Int = 6,
        minTextScore: Double = 0.6
    ) -> [LyricBlock] {
        let B = blocks.count
        let S = segments.count
        var result = blocks
        var minSegStart = 0
        var anchorCount = 0

        // Position prior so unique blocks prefer the earlier audio instance when
        // a phrase recurs (whisper often re-transcribes pre-chorus/bridge lines
        // similarly across repetitions; without this prior, the greedy picks the
        // later one if its text score is marginally higher).
        let lyricSpan = max(0.1, (segments.last?.endTime ?? 0) - (segments.first?.startTime ?? 0))
        let vocalStart = segments.first?.startTime ?? 0
        let posSigma: Double = 30.0

        for bi in 0..<B {
            // Respect manual overrides and advance the monotonic floor past them
            if result[bi].isManuallyAdjusted, let endT = result[bi].endTime {
                if let adv = segments.firstIndex(where: { $0.startTime >= endT }) {
                    minSegStart = max(minSegStart, adv)
                }
                continue
            }

            guard bi < repetitions.count, repetitions[bi] == 1 else { continue }

            let blockText = blocks[bi].japanese
            let normalizedLength = JapaneseTextNormalizer.normalize(blockText).count
            guard normalizedLength >= minTextLength else { continue }

            let expectedTime = vocalStart + (Double(bi) + 0.5) / Double(B) * lyricSpan

            var best: (segStart: Int, segEnd: Int, score: Double)? = nil
            for si in minSegStart..<S {
                if isNonSpeechSegment(segments[si]) { continue }
                let maxSpan = min(mode.maxCombineSegments, S - si)
                for span in 1...maxSpan {
                    let endSeg = si + span - 1
                    if span > 1 && isNonSpeechSegment(segments[endSeg]) { break }
                    let combinedText = (si...endSeg).map { segments[$0].text }.joined()
                    let textScore = JapaneseTextNormalizer.similarity(blockText, combinedText)
                    if textScore < minTextScore { continue }

                    let segMid = (segments[si].startTime + segments[endSeg].endTime) / 2.0
                    let dist = abs(segMid - expectedTime)
                    let posScore = exp(-(dist * dist) / (2 * posSigma * posSigma))

                    let conf = spanConfidenceFactor(segments: segments, si: si, endSeg: endSeg)
                    let combined = textScore * 0.6 + posScore * 0.4
                    let scored = combined * conf

                    if best == nil || scored > best!.score {
                        best = (si, endSeg, scored)
                    }
                }
            }

            if let b = best {
                result[bi].startTime = segments[b.segStart].startTime
                result[bi].endTime = segments[b.segEnd].endTime
                result[bi].confidence = b.score
                result[bi].isAnchor = true
                minSegStart = b.segEnd + 1
                anchorCount += 1
            }
        }

        if anchorCount > 0 {
            print("[Alignment] Pre-anchored \(anchorCount) unique blocks (greedy text-best)")
        }
        return result
    }

    /// Align whisper segments to lyric blocks using multi-pass position-aware DP.
    ///
    /// Key improvements over simple beam search:
    /// 1. Position-aware scoring — candidates near expected timeline position score higher
    /// 2. Windowed search — only search segments within a temporal window
    /// 3. Multi-pass refinement — first pass finds anchors, subsequent passes fill gaps
    /// 4. Recovery from bad regions — low-confidence regions are re-aligned locally
    static func align(
        segments: [WhisperSegment],
        to blocks: [LyricBlock],
        mode: AlignmentQualityMode = .legacy,
        ignoreRegions: [IgnoreRegion] = [],
        onProgress: ((String) -> Void)? = nil
    ) -> [LyricBlock] {
        guard !segments.isEmpty, !blocks.isEmpty else { return blocks }

        // Reset auto-set anchors from prior runs so the new alignment can place
        // them freshly. User anchors and manual overrides are preserved.
        var blocks = blocks
        for i in blocks.indices where !blocks[i].isUserAnchor && !blocks[i].isManuallyAdjusted {
            blocks[i].isAnchor = false
        }

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

        // Per-block repetition counts — stable across passes since block text doesn't change.
        let repetitions = repetitionCounts(blocks)

        // === Phase 0: Pre-anchor unique blocks (verses, bridges) ===
        // Chorus blocks repeat and are ambiguous; verses don't. Anchoring uniques
        // first gives the DP reliable time references so chorus instances land
        // on the correct repetition — preventing the chorus domino cascade.
        let preAnchored = greedyAnchorUniqueBlocks(
            segments: segments,
            blocks: blocks,
            repetitions: repetitions,
            mode: mode
        )

        // === Pass 1: Position-aware DP alignment ===
        var alignedBlocks = positionAwareDP(
            segments: segments,
            blocks: preAnchored,
            totalDuration: totalDuration,
            vocalOnset: vocalOnset,
            mode: mode,
            repetitionCounts: repetitions,
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
                repetitionCounts: repetitions,
                passNumber: pass
            )
        }

        // === Pass 3: Drift detection & local re-anchor ===
        let driftResult = detectAndCorrectDrift(
            blocks: &alignedBlocks,
            segments: segments,
            totalDuration: totalDuration,
            vocalOnset: vocalOnset,
            mode: mode,
            repetitionCounts: repetitions
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
        let regionRepetitions = Array(repetitionCounts(allBlocks)[fromIndex...toIndex])

        print("[LocalRealign] Re-aligning blocks \(fromIndex)–\(toIndex) in time range \(String(format: "%.1f", timeBefore))–\(String(format: "%.1f", timeAfter))s (\(regionSegments.count) segments)")

        let localAligned = alignRegion(
            segments: regionSegments,
            blocks: regionBlocks,
            regionStart: timeBefore,
            regionEnd: timeAfter,
            regionDuration: regionDuration,
            mode: mode,
            repetitionCounts: regionRepetitions
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
}
