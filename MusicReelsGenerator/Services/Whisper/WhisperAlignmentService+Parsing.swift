import Foundation

extension WhisperAlignmentService {
    /// Parse whisper-cpp's --output-json-full result. Each segment's confidence
    /// is the mean probability of its real (non-special) tokens. Special tokens
    /// like `[_BEG_]` and `[_TT_NNN]` are excluded because they're metadata.
    /// Sanitizes UTF-8 first because whisper-cpp can emit token text that splits
    /// multibyte chars (e.g. kanji), producing invalid UTF-8 that fails strict parsing.
    static func parseJSON(_ data: Data) -> [WhisperSegment] {
        // Lossy UTF-8 decode replaces invalid byte sequences with U+FFFD,
        // letting JSON parsing succeed even when whisper output is malformed.
        let sanitized = Data(String(decoding: data, as: UTF8.self).utf8)
        guard let obj = try? JSONSerialization.jsonObject(with: sanitized) as? [String: Any],
              let transcription = obj["transcription"] as? [[String: Any]] else {
            return []
        }

        var segments: [WhisperSegment] = []
        for seg in transcription {
            guard let offsets = seg["offsets"] as? [String: Any],
                  let fromMs = (offsets["from"] as? NSNumber)?.doubleValue,
                  let toMs = (offsets["to"] as? NSNumber)?.doubleValue,
                  let rawText = seg["text"] as? String else {
                continue
            }
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }

            var confidence: Double? = nil
            if let tokens = seg["tokens"] as? [[String: Any]] {
                var probs: [Double] = []
                probs.reserveCapacity(tokens.count)
                for tok in tokens {
                    guard let tt = tok["text"] as? String,
                          let p = (tok["p"] as? NSNumber)?.doubleValue else { continue }
                    let trimmed = tt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasPrefix("[_") && trimmed.hasSuffix("]") { continue }
                    probs.append(p)
                }
                if !probs.isEmpty {
                    confidence = probs.reduce(0, +) / Double(probs.count)
                }
            }

            segments.append(WhisperSegment(
                startTime: fromMs / 1000.0,
                endTime: toMs / 1000.0,
                text: text,
                confidence: confidence
            ))
        }
        return segments
    }

    static func parseCSV(_ csv: String) -> [WhisperSegment] {
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

    static func parseStdout(_ output: String) -> [WhisperSegment] {
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
