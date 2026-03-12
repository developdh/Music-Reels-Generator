import Foundation

/// Errors specific to the advanced Python-based alignment pipeline.
enum AdvancedAlignmentError: LocalizedError {
    case pythonNotFound
    case scriptNotFound(String)
    case pipelineFailed(String)
    case outputParsingFailed(String)
    case dependenciesMissing(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3 not found. Install with: brew install python3"
        case .scriptNotFound(let path):
            return "Alignment script not found at: \(path). Ensure Scripts/alignment_pipeline.py exists."
        case .pipelineFailed(let msg):
            return "Alignment pipeline failed: \(msg)"
        case .outputParsingFailed(let msg):
            return "Failed to parse alignment output: \(msg)"
        case .dependenciesMissing(let msg):
            return msg
        }
    }
}

/// Result from the advanced alignment pipeline, parsed from JSON.
struct AdvancedAlignmentResult: Codable {
    let version: Int?
    let lines: [AlignedLineResult]
    let debug: AlignmentDebugInfo?
    let error: String?

    struct AlignedLineResult: Codable {
        let index: Int
        let startTime: Double
        let endTime: Double
        let confidence: Double
        let isAnchor: Bool
        let method: String

        enum CodingKeys: String, CodingKey {
            case index
            case startTime = "start_time"
            case endTime = "end_time"
            case confidence
            case isAnchor = "is_anchor"
            case method
        }
    }

    struct AlignmentDebugInfo: Codable {
        let vocalOnset: Double?
        let totalDuration: Double?
        let totalWords: Int?
        let mode: String?
        let strategy: String?
        let whisperModel: String?
        let vocalSeparationUsed: Bool?
        let stemForAlignment: Bool?
        let methodCounts: [String: Int]?
        let binMetrics: [BinMetric]?
        let chunks: [ChunkInfo]?
        let collapseRegions: [CollapseRegion]?

        enum CodingKeys: String, CodingKey {
            case vocalOnset = "vocal_onset"
            case totalDuration = "total_duration"
            case totalWords = "total_words"
            case mode, strategy
            case whisperModel = "whisper_model"
            case vocalSeparationUsed = "vocal_separation_used"
            case stemForAlignment = "stem_for_alignment"
            case methodCounts = "method_counts"
            case binMetrics = "bin_metrics"
            case chunks
            case collapseRegions = "collapse_regions"
        }

        struct BinMetric: Codable {
            let bin: String
            let lineCount: Int?
            let meanConfidence: Double?
            let anchors: Int?
            let forced: Int?
            let recovered: Int?
            let interpolated: Int?
            let collapseCount: Int?

            enum CodingKeys: String, CodingKey {
                case bin
                case lineCount = "line_count"
                case meanConfidence = "mean_confidence"
                case anchors, forced, recovered, interpolated
                case collapseCount = "collapse_count"
            }
        }

        struct ChunkInfo: Codable {
            let index: Int?
            let start: Double?
            let end: Double?
            let words: Int?
            let chosenWindow: String?
            let alignmentScore: Double?

            enum CodingKeys: String, CodingKey {
                case index, start, end, words
                case chosenWindow = "chosen_window"
                case alignmentScore = "alignment_score"
            }
        }

        struct CollapseRegion: Codable {
            let startLine: Int?
            let endLine: Int?

            enum CodingKeys: String, CodingKey {
                case startLine = "start_line"
                case endLine = "end_line"
            }
        }
    }
}

/// Service that runs the advanced Python-based forced alignment pipeline.
/// Used for Balanced, Accurate, and Maximum quality modes.
enum AdvancedAlignmentService {

    // MARK: - Python / Script Discovery

    private static func findPython() -> String? {
        ProcessRunner.findPython()
    }

    private static func findScript() -> String? {
        // Look relative to the executable, then in common dev paths
        let fm = FileManager.default

        // 1. Check relative to the process working directory
        let cwd = fm.currentDirectoryPath
        let cwdPath = (cwd as NSString).appendingPathComponent("Scripts/alignment_pipeline.py")
        if fm.fileExists(atPath: cwdPath) { return cwdPath }

        // 2. Check in the source tree (for dev builds)
        // Walk up from the executable to find the project root
        if let execURL = Bundle.main.executableURL {
            var dir = execURL.deletingLastPathComponent()
            for _ in 0..<5 {
                let candidate = dir.appendingPathComponent("Scripts/alignment_pipeline.py").path
                if fm.fileExists(atPath: candidate) { return candidate }
                dir = dir.deletingLastPathComponent()
            }
        }

        // 3. Check in the app bundle Resources
        if let bundlePath = Bundle.main.path(forResource: "alignment_pipeline", ofType: "py") {
            return bundlePath
        }

        // 4. Check in common project locations
        let home = fm.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "\(home)/project/Music-Reels-Generator/Scripts/alignment_pipeline.py",
            "/Users/dh/project/Music-Reels-Generator/Scripts/alignment_pipeline.py",
        ]
        return commonPaths.first { fm.fileExists(atPath: $0) }
    }

    /// Check if the advanced pipeline is available (Python + script + whisper module).
    static var isAvailable: Bool {
        guard let python = findPython(), findScript() != nil else { return false }

        // Quick check: can Python import whisper?
        let task = Process()
        task.executableURL = URL(fileURLWithPath: python)
        task.arguments = ["-c", "import whisper"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Public API

    /// Run the advanced forced alignment pipeline.
    ///
    /// - Parameters:
    ///   - audioURL: Path to 16kHz mono WAV file
    ///   - lyrics: Lyric blocks to align
    ///   - mode: Quality mode (balanced, accurate, maximum)
    ///   - onProgress: Progress callback
    /// - Returns: Aligned lyric blocks with timing data
    static func align(
        audioURL: URL,
        lyrics: [LyricBlock],
        mode: AlignmentQualityMode,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> [LyricBlock] {
        guard let python = findPython() else {
            throw AdvancedAlignmentError.pythonNotFound
        }

        guard let scriptPath = findScript() else {
            throw AdvancedAlignmentError.scriptNotFound("Scripts/alignment_pipeline.py")
        }

        // Prepare lyrics JSON input
        let lyricsJSON = lyrics.map { block -> [String: String] in
            ["japanese": block.japanese, "korean": block.korean]
        }

        let tempDir = NSTemporaryDirectory()
        let lyricsInputPath = tempDir + "alignment_lyrics_\(UUID().uuidString).json"
        let outputPath = tempDir + "alignment_output_\(UUID().uuidString).json"

        let lyricsData = try JSONSerialization.data(
            withJSONObject: lyricsJSON, options: [.prettyPrinted]
        )
        try lyricsData.write(to: URL(fileURLWithPath: lyricsInputPath))

        defer {
            try? FileManager.default.removeItem(atPath: lyricsInputPath)
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        // Build arguments
        let modeStr = mode.pipelineModeName
        var args = [
            scriptPath,
            "--audio", audioURL.path,
            "--lyrics", lyricsInputPath,
            "--mode", modeStr,
            "--output", outputPath,
        ]

        // Use specific whisper model if user has a preference
        if let modelOverride = mode.whisperModelOverride {
            args += ["--whisper-model", modelOverride]
        }

        onProgress?("Starting advanced alignment pipeline (\(mode.rawValue) mode)...")

        // Run Python pipeline with streaming progress
        let result = try await runWithProgress(
            python: python,
            arguments: args,
            onProgress: onProgress
        )

        // Check for errors
        if !result.succeeded {
            // Check if error is about missing dependencies
            if result.stderr.contains("Missing required packages") {
                let msg = result.stderr
                    .components(separatedBy: "\n")
                    .first { $0.contains("Missing required packages") }
                    ?? result.stderr
                throw AdvancedAlignmentError.dependenciesMissing(msg)
            }
            throw AdvancedAlignmentError.pipelineFailed(
                result.stderr.suffix(500).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // Parse output JSON
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw AdvancedAlignmentError.pipelineFailed("No output file produced")
        }

        let outputData = try Data(contentsOf: URL(fileURLWithPath: outputPath))
        let alignmentResult: AdvancedAlignmentResult

        do {
            alignmentResult = try JSONDecoder().decode(
                AdvancedAlignmentResult.self, from: outputData
            )
        } catch {
            throw AdvancedAlignmentError.outputParsingFailed(error.localizedDescription)
        }

        // Check for pipeline-level error
        if let pipelineError = alignmentResult.error {
            throw AdvancedAlignmentError.dependenciesMissing(pipelineError)
        }

        // Apply results to lyric blocks
        var alignedBlocks = lyrics
        for lineResult in alignmentResult.lines {
            guard lineResult.index < alignedBlocks.count else { continue }

            let idx = lineResult.index

            // Don't overwrite manually adjusted blocks
            if alignedBlocks[idx].isManuallyAdjusted { continue }

            alignedBlocks[idx].startTime = lineResult.startTime > 0 ? lineResult.startTime : nil
            alignedBlocks[idx].endTime = lineResult.endTime > 0 ? lineResult.endTime : nil
            alignedBlocks[idx].confidence = lineResult.confidence
            alignedBlocks[idx].isAnchor = lineResult.isAnchor
        }

        // Log debug summary
        if let debug = alignmentResult.debug {
            printDebugReport(debug, blockCount: lyrics.count)
        }

        let matched = alignedBlocks.filter { ($0.confidence ?? 0) > 0.3 }.count
        let highConf = alignedBlocks.filter { ($0.confidence ?? 0) >= 0.6 }.count
        onProgress?("Advanced alignment complete: \(matched)/\(lyrics.count) matched (\(highConf) high-confidence)")

        return alignedBlocks
    }

    // MARK: - Subprocess with Progress

    private static func runWithProgress(
        python: String,
        arguments: [String],
        onProgress: ((String) -> Void)?
    ) async throws -> ProcessResult {
        // Use streaming variant so stderr [PROGRESS] lines are delivered live
        let result = try await ProcessRunner.runStreaming(
            python,
            arguments: arguments,
            timeout: 600 // 10 minute timeout for large files
        ) { line in
            if line.hasPrefix("[PROGRESS] ") {
                let msg = String(line.dropFirst("[PROGRESS] ".count))
                // Deliver progress on main actor since UI observes it
                Task { @MainActor in
                    onProgress?(msg)
                }
            }
        }

        return result
    }

    // MARK: - Debug Reporting

    private static func printDebugReport(
        _ debug: AdvancedAlignmentResult.AlignmentDebugInfo,
        blockCount: Int
    ) {
        print("\n=== ADVANCED ALIGNMENT REPORT ===")
        print("Mode: \(debug.mode ?? "unknown"), Strategy: \(debug.strategy ?? "unknown"), Model: \(debug.whisperModel ?? "unknown")")
        if let stemUsed = debug.vocalSeparationUsed, stemUsed {
            print("Vocal separation: YES, used for alignment: \(debug.stemForAlignment == true ? "YES" : "NO")")
        }
        print("Vocal onset: \(debug.vocalOnset.map { String(format: "%.2f", $0) } ?? "?")s")
        print("Total words: \(debug.totalWords ?? 0)")

        if let methods = debug.methodCounts {
            print("Methods: \(methods)")
        }

        if let bins = debug.binMetrics {
            print("\nPer-region metrics:")
            for bin in bins {
                let conf = bin.meanConfidence.map { String(format: "%.2f", $0) } ?? "?"
                print("  \(bin.bin): conf=\(conf), "
                      + "lines=\(bin.lineCount ?? 0), "
                      + "anchors=\(bin.anchors ?? 0), "
                      + "collapse=\(bin.collapseCount ?? 0)")
            }
        }

        if let collapsed = debug.collapseRegions, !collapsed.isEmpty {
            print("\nCollapse regions detected:")
            for region in collapsed {
                print("  Lines \(region.startLine ?? 0)–\(region.endLine ?? 0)")
            }
        }

        if let chunks = debug.chunks, !chunks.isEmpty {
            print("\nChunks: \(chunks.count)")
            for chunk in chunks.prefix(20) {
                print("  [\(chunk.index ?? 0)] "
                      + "\(String(format: "%.1f", chunk.start ?? 0))–"
                      + "\(String(format: "%.1f", chunk.end ?? 0))s, "
                      + "\(chunk.words ?? 0) words, "
                      + "\(chunk.chosenWindow ?? "skipped"), "
                      + "score=\(String(format: "%.3f", chunk.alignmentScore ?? 0))")
            }
        }

        print("=== END ADVANCED REPORT ===\n")
    }
}
