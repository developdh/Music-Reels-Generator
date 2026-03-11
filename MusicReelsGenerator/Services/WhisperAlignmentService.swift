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
            "--no-timestamps", "false",
            "--print-progress", "false"
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

    /// Align whisper segments to lyric blocks using fuzzy matching
    static func align(
        segments: [WhisperSegment],
        to blocks: [LyricBlock],
        onProgress: ((String) -> Void)? = nil
    ) -> [LyricBlock] {
        guard !segments.isEmpty, !blocks.isEmpty else { return blocks }

        onProgress?("Aligning \(segments.count) segments to \(blocks.count) lyric blocks...")

        // Build a combined transcript with timing
        var alignedBlocks = blocks
        var segmentIndex = 0

        for blockIndex in 0..<alignedBlocks.count {
            guard !alignedBlocks[blockIndex].isManuallyAdjusted else { continue }

            let blockText = alignedBlocks[blockIndex].japanese
            var bestScore: Double = 0
            var bestSegmentStart: Double?
            var bestSegmentEnd: Double?

            // Try matching against segments starting from current position
            // Use a sliding window approach
            let searchEnd = min(segmentIndex + segments.count, segments.count)

            for i in segmentIndex..<searchEnd {
                let segText = segments[i].text
                let score = JapaneseTextNormalizer.similarity(blockText, segText)

                if score > bestScore {
                    bestScore = score
                    bestSegmentStart = segments[i].startTime
                    bestSegmentEnd = segments[i].endTime
                }

                // Try combining consecutive segments for longer lyrics
                if i + 1 < segments.count {
                    let combined = segText + segments[i + 1].text
                    let combinedScore = JapaneseTextNormalizer.similarity(blockText, combined)
                    if combinedScore > bestScore {
                        bestScore = combinedScore
                        bestSegmentStart = segments[i].startTime
                        bestSegmentEnd = segments[i + 1].endTime
                    }
                }
            }

            // If we found a reasonable match, use it
            if bestScore > 0.2, let start = bestSegmentStart, let end = bestSegmentEnd {
                alignedBlocks[blockIndex].startTime = start
                alignedBlocks[blockIndex].endTime = end
                alignedBlocks[blockIndex].confidence = bestScore

                // Advance segment index to avoid double-matching
                if let matchedIdx = (segmentIndex..<searchEnd).first(where: {
                    segments[$0].startTime == start
                }) {
                    segmentIndex = matchedIdx + 1
                }
            } else {
                alignedBlocks[blockIndex].confidence = 0
            }
        }

        // Post-process: fill gaps by distributing time evenly for unmatched blocks
        fillTimingGaps(&alignedBlocks, totalDuration: segments.last?.endTime ?? 0)

        onProgress?("Alignment complete.")
        return alignedBlocks
    }

    /// Fill timing gaps for blocks that didn't match
    private static func fillTimingGaps(_ blocks: inout [LyricBlock], totalDuration: Double) {
        guard !blocks.isEmpty else { return }

        // Find runs of unmatched blocks between matched ones
        var i = 0
        while i < blocks.count {
            if blocks[i].startTime != nil {
                i += 1
                continue
            }

            // Find the run of unmatched blocks
            var runEnd = i
            while runEnd < blocks.count && blocks[runEnd].startTime == nil {
                runEnd += 1
            }

            // Determine time bounds for interpolation
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
            let duration = endBound - startBound
            let blockDuration = duration / Double(runLength)

            for j in 0..<runLength {
                let idx = i + j
                blocks[idx].startTime = startBound + Double(j) * blockDuration
                blocks[idx].endTime = startBound + Double(j + 1) * blockDuration
                blocks[idx].confidence = 0.1 // Very low confidence for interpolated
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
