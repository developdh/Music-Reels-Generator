import Foundation

enum SubtitleImportError: LocalizedError {
    case unsupportedFormat
    case readFailed(String)
    case noCues

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported subtitle format. Use .srt or .lrc."
        case .readFailed(let msg):
            return "Failed to read subtitle file: \(msg)"
        case .noCues:
            return "No usable cues found in the subtitle file."
        }
    }
}

/// Parses LRC / SRT subtitle files into timed `LyricBlock`s.
/// Imported blocks carry `confidence = 1.0` and are flagged as fully manually adjusted
/// so they qualify as trusted anchors for piecewise correction.
enum SubtitleImportService {

    static func importFile(url: URL) throws -> [LyricBlock] {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw SubtitleImportError.readFailed(error.localizedDescription)
        }

        let ext = url.pathExtension.lowercased()
        let blocks: [LyricBlock]
        switch ext {
        case "srt":
            blocks = parseSRT(content)
        case "lrc":
            blocks = parseLRC(content)
        default:
            // Sniff: any line starts with `[mm:ss` → LRC; presence of ` --> ` → SRT
            if content.contains(" --> ") {
                blocks = parseSRT(content)
            } else if content.range(of: #"\[\d{1,3}:\d{2}"#, options: .regularExpression) != nil {
                blocks = parseLRC(content)
            } else {
                throw SubtitleImportError.unsupportedFormat
            }
        }

        guard !blocks.isEmpty else { throw SubtitleImportError.noCues }
        return blocks
    }

    // MARK: - SRT

    static func parseSRT(_ content: String) -> [LyricBlock] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Cue separator: blank line. Allow optional surrounding whitespace.
        let cues = normalized.components(separatedBy: "\n\n")

        var blocks: [LyricBlock] = []
        for rawCue in cues {
            let trimmed = rawCue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var lines = trimmed.components(separatedBy: "\n")
            // Optional leading index line (purely digits)
            if let first = lines.first,
               Int(first.trimmingCharacters(in: .whitespaces)) != nil {
                lines.removeFirst()
            }

            guard let timestampLine = lines.first,
                  let (start, end) = parseSRTTimestampLine(timestampLine) else { continue }
            lines.removeFirst()

            let textLines = lines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let primary = textLines.first else { continue }
            // Treat first line as primary, remaining lines (if any) joined as secondary.
            let secondary: String
            if textLines.count >= 2 {
                secondary = textLines[1...].joined(separator: " ")
            } else {
                secondary = ""
            }

            blocks.append(makeBlock(primary: primary, secondary: secondary, start: start, end: end))
        }
        return blocks
    }

    /// Accepts `HH:MM:SS,mmm --> HH:MM:SS,mmm` and the dot-decimal variant.
    private static func parseSRTTimestampLine(_ line: String) -> (Double, Double)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        guard let s = parseSRTTimestamp(parts[0]),
              let e = parseSRTTimestamp(parts[1]) else { return nil }
        guard e > s else { return nil }
        return (s, e)
    }

    private static func parseSRTTimestamp(_ raw: String) -> Double? {
        // Take the first whitespace-separated token (drops position metadata like `X1:0 X2:0 ...`).
        let token = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces).first ?? ""
        // Normalize comma → dot for fractional seconds.
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        let parts = normalized.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard let s = Int(secParts[0]) else { return nil }
        var frac = 0.0
        if secParts.count >= 2, let val = Int(secParts[1]) {
            let div = pow(10.0, Double(secParts[1].count))
            frac = Double(val) / div
        }
        return Double(h) * 3600 + Double(m) * 60 + Double(s) + frac
    }

    // MARK: - LRC

    static func parseLRC(_ content: String) -> [LyricBlock] {
        let timestampRegex: NSRegularExpression
        do {
            timestampRegex = try NSRegularExpression(
                pattern: #"\[(\d{1,3}):(\d{2})(?:[\.:](\d{1,3}))?\]"#
            )
        } catch {
            return []
        }

        struct Entry {
            let time: Double
            let text: String
        }
        var entries: [Entry] = []

        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = timestampRegex.matches(in: line, range: fullRange)
            guard !matches.isEmpty else { continue }
            // Only consider leading consecutive timestamp tags.
            var consumed = 0
            var leading: [NSTextCheckingResult] = []
            for m in matches {
                if m.range.location != consumed { break }
                leading.append(m)
                consumed = m.range.location + m.range.length
            }
            guard !leading.isEmpty else { continue }

            let text = nsLine.substring(from: consumed).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }

            for m in leading {
                guard let time = parseLRCTimestamp(match: m, in: nsLine) else { continue }
                entries.append(Entry(time: time, text: text))
            }
        }

        entries.sort { $0.time < $1.time }
        guard !entries.isEmpty else { return [] }

        // Group consecutive entries with the same timestamp (within tolerance) as
        // primary + secondary lines.
        let tolerance = 0.01
        var blocks: [LyricBlock] = []
        var i = 0
        while i < entries.count {
            let start = entries[i].time
            let primary = entries[i].text
            var secondaryParts: [String] = []
            i += 1
            while i < entries.count, abs(entries[i].time - start) <= tolerance {
                secondaryParts.append(entries[i].text)
                i += 1
            }
            // End time: next group's start, or +5s for the final cue.
            let end: Double
            if i < entries.count {
                end = max(start + 0.1, entries[i].time)
            } else {
                end = start + 5.0
            }
            let secondary = secondaryParts.joined(separator: " ")
            blocks.append(makeBlock(primary: primary, secondary: secondary, start: start, end: end))
        }
        return blocks
    }

    private static func parseLRCTimestamp(match: NSTextCheckingResult, in nsLine: NSString) -> Double? {
        guard match.numberOfRanges >= 3 else { return nil }
        let mins = Int(nsLine.substring(with: match.range(at: 1))) ?? 0
        let secs = Int(nsLine.substring(with: match.range(at: 2))) ?? 0
        var frac = 0.0
        if match.numberOfRanges >= 4 {
            let fracRange = match.range(at: 3)
            if fracRange.location != NSNotFound {
                let digits = nsLine.substring(with: fracRange)
                if let val = Int(digits) {
                    let div = pow(10.0, Double(digits.count))
                    frac = Double(val) / div
                }
            }
        }
        return Double(mins) * 60 + Double(secs) + frac
    }

    // MARK: - Block construction

    private static func makeBlock(primary: String, secondary: String, start: Double, end: Double) -> LyricBlock {
        LyricBlock(
            japanese: primary,
            korean: secondary,
            startTime: start,
            endTime: end,
            confidence: 1.0,
            manuallyAdjustedStart: true,
            manuallyAdjustedEnd: true,
            isAnchor: true,
            isUserAnchor: false
        )
    }
}
