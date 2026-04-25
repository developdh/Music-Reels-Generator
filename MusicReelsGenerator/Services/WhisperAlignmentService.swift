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

        // Output CSV format for easy parsing
        let outputBase = NSTemporaryDirectory() + "whisper_output"

        var args = [
            "-m", model,
            "-f", audioURL.path,
            "--output-csv",
            "--output-file", outputBase,
            "--no-prints"
        ]
        if let language {
            args.insert(contentsOf: ["-l", language], at: 4)
        }

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
}
