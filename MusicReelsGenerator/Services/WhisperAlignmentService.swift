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
    /// Default model search paths
    static var modelSearchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/share/whisper-cpp/models/ggml-medium.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-large-v3.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-small.bin",
            "\(home)/.local/share/whisper-cpp/models/ggml-base.bin",
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

        onProgress?("Running speech recognition...")

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

        // whisper-cpp may output to stdout in some versions
        // Try parsing CSV file first, fall back to stdout
        let csvPath = outputBase + ".csv"
        var segments: [WhisperSegment] = []

        if FileManager.default.fileExists(atPath: csvPath),
           let csvContent = try? String(contentsOfFile: csvPath, encoding: .utf8) {
            segments = parseCSV(csvContent)
            try? FileManager.default.removeItem(atPath: csvPath)
        }

        // If CSV parsing didn't work, try parsing stdout (SRT-like format)
        if segments.isEmpty {
            segments = parseStdout(result.stdout)
        }

        if segments.isEmpty && !result.succeeded {
            throw WhisperError.transcriptionFailed(result.stderr)
        }

        if segments.isEmpty {
            throw WhisperError.noSegmentsFound
        }

        onProgress?("Found \(segments.count) speech segments.")
        return segments
    }

    // MARK: - Monotonic DP Alignment

    /// A candidate match: segment range mapped to a block
    private struct SegmentMatch {
        let segStart: Int   // first segment index
        let segEnd: Int     // last segment index (inclusive)
        let score: Double
        var startTime: Double
        var endTime: Double
    }

    /// Align whisper segments to lyric blocks using monotonic DP matching.
    /// Guarantees: monotonically increasing timing, local search windows,
    /// anchor-based interpolation for unmatched blocks.
    static func align(
        segments: [WhisperSegment],
        to blocks: [LyricBlock],
        onProgress: ((String) -> Void)? = nil
    ) -> [LyricBlock] {
        guard !segments.isEmpty, !blocks.isEmpty else { return blocks }

        let B = blocks.count
        let S = segments.count
        onProgress?("Aligning \(S) segments to \(B) lyric blocks (DP)...")

        // Step 1: Build score matrix — for each block, find best match at each segment position
        // We allow matching 1, 2, or 3 consecutive segments to handle whisper splitting lines
        let maxCombine = 3
        let matchThreshold = 0.25

        // For each block, collect candidate matches
        var candidates: [[SegmentMatch]] = Array(repeating: [], count: B)

        for bi in 0..<B {
            if blocks[bi].isManuallyAdjusted { continue }

            let blockText = blocks[bi].japanese

            for si in 0..<S {
                // Try combining 1..maxCombine consecutive segments
                for span in 1...maxCombine {
                    let endSeg = si + span - 1
                    guard endSeg < S else { break }

                    let combinedText = (si...endSeg).map { segments[$0].text }.joined()
                    let score = JapaneseTextNormalizer.similarity(blockText, combinedText)

                    if score >= matchThreshold {
                        candidates[bi].append(SegmentMatch(
                            segStart: si,
                            segEnd: endSeg,
                            score: score,
                            startTime: segments[si].startTime,
                            endTime: segments[endSeg].endTime
                        ))
                    }
                }
            }
        }

        // Step 2: Monotonic DP
        // dp[bi] = best total score using blocks 0..bi, with the constraint
        // that matched segments are monotonically increasing.
        // For each block we either skip it (no match) or pick one of its candidates.
        // If matched, the segment position must be > the last matched segment position.

        // State: (bestScore, lastSegEnd, assignments)
        // To keep it tractable, track per-block: best score achievable, which candidate was chosen

        struct DPState {
            var totalScore: Double
            var lastSegEnd: Int  // last matched segment end index, -1 if none
            var choices: [Int?]  // for each block: index into candidates[bi], or nil if skipped
        }

        // Forward pass with pruning: for each block, decide match or skip
        // We keep a small set of best states to avoid exponential blowup
        let maxStates = 50  // beam width

        var beam: [DPState] = [DPState(totalScore: 0, lastSegEnd: -1, choices: [])]

        for bi in 0..<B {
            onProgress?("Aligning block \(bi + 1)/\(B)...")

            var nextBeam: [DPState] = []

            for state in beam {
                // Option 1: Skip this block (no match)
                var skipped = state
                skipped.choices.append(nil)
                nextBeam.append(skipped)

                // Option 2: Match with a candidate (must be monotonically after lastSegEnd)
                if !blocks[bi].isManuallyAdjusted {
                    for (ci, cand) in candidates[bi].enumerated() {
                        if cand.segStart > state.lastSegEnd {
                            var matched = state
                            matched.totalScore += cand.score
                            matched.lastSegEnd = cand.segEnd
                            matched.choices.append(ci)
                            nextBeam.append(matched)
                        }
                    }
                } else {
                    // Manually adjusted blocks keep their timing; treat as anchors
                    // but don't consume segments — just pass through
                }
            }

            // Prune beam: keep top states by score
            nextBeam.sort { $0.totalScore > $1.totalScore }
            beam = Array(nextBeam.prefix(maxStates))
        }

        // Pick best final state
        guard let best = beam.first else { return blocks }

        // Step 3: Apply DP result
        var alignedBlocks = blocks

        for bi in 0..<B {
            guard !alignedBlocks[bi].isManuallyAdjusted else {
                alignedBlocks[bi].isAnchor = true
                continue
            }

            if let ci = best.choices[bi], let cand = candidates[bi][safe: ci] {
                alignedBlocks[bi].startTime = cand.startTime
                alignedBlocks[bi].endTime = cand.endTime
                alignedBlocks[bi].confidence = cand.score
                alignedBlocks[bi].isAnchor = cand.score >= 0.6
            } else {
                alignedBlocks[bi].startTime = nil
                alignedBlocks[bi].endTime = nil
                alignedBlocks[bi].confidence = 0
                alignedBlocks[bi].isAnchor = false
            }
        }

        // Step 4: Anchor-based interpolation for unmatched blocks
        interpolateFromAnchors(&alignedBlocks, totalDuration: segments.last?.endTime ?? 0)

        let matched = alignedBlocks.filter { ($0.confidence ?? 0) >= matchThreshold }.count
        onProgress?("Alignment complete: \(matched)/\(B) blocks matched.")
        return alignedBlocks
    }

    /// Interpolate timing for unmatched blocks using surrounding anchors.
    /// Uses proportional spacing based on text length rather than equal distribution.
    private static func interpolateFromAnchors(_ blocks: inout [LyricBlock], totalDuration: Double) {
        guard !blocks.isEmpty else { return }

        var i = 0
        while i < blocks.count {
            // Skip blocks that already have timing
            if blocks[i].startTime != nil {
                i += 1
                continue
            }

            // Find the run of unmatched blocks
            var runEnd = i
            while runEnd < blocks.count && blocks[runEnd].startTime == nil {
                runEnd += 1
            }

            // Determine time bounds from surrounding anchors
            let startBound: Double
            if i > 0, let prevEnd = blocks[i - 1].endTime {
                startBound = prevEnd
            } else {
                startBound = 0
            }

            let endBound: Double
            if runEnd < blocks.count, let nextStart = blocks[runEnd].startTime {
                endBound = nextStart
            } else {
                endBound = totalDuration
            }

            let runLength = runEnd - i
            let availableDuration = endBound - startBound

            // Proportional distribution based on Japanese text length
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
                    blocks[idx].confidence = 0.05 // Very low — interpolated
                    cursor += blockDuration
                }
            } else {
                // Equal distribution fallback
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

    // MARK: - Parsing

    private static func parseCSV(_ csv: String) -> [WhisperSegment] {
        let lines = csv.components(separatedBy: .newlines)
        var segments: [WhisperSegment] = []

        for line in lines.dropFirst() { // Skip header
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3 else { continue }

            // CSV format: start,end,text
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
        // Parse whisper.cpp default output format:
        // [00:00:00.000 --> 00:00:02.000]  テキスト
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
