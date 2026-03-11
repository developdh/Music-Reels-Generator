import Foundation

enum LyricsParseError: LocalizedError {
    case oddNumberOfLines(count: Int)
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .oddNumberOfLines(let count):
            return "Lyrics have \(count) non-empty lines. Each block needs exactly 2 lines (Japanese + Korean). Check for missing translations."
        case .emptyInput:
            return "No lyrics text provided."
        }
    }
}

enum LyricsParserService {
    /// Parse bilingual lyrics from the expected format:
    /// <Japanese line>
    /// <Korean line>
    /// (blank line)
    /// <Japanese line>
    /// <Korean line>
    static func parse(_ text: String) throws -> [LyricBlock] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LyricsParseError.emptyInput
        }

        // Split into lines, group non-empty lines into blocks separated by blank lines
        let allLines = trimmed.components(separatedBy: .newlines)

        var blocks: [LyricBlock] = []
        var currentPair: [String] = []

        for line in allLines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty {
                // End of a block — flush if we have lines
                if !currentPair.isEmpty {
                    if currentPair.count % 2 != 0 {
                        throw LyricsParseError.oddNumberOfLines(count: currentPair.count)
                    }
                    for i in stride(from: 0, to: currentPair.count, by: 2) {
                        blocks.append(LyricBlock(
                            japanese: currentPair[i],
                            korean: currentPair[i + 1]
                        ))
                    }
                    currentPair = []
                }
            } else {
                currentPair.append(stripped)
            }
        }

        // Flush remaining
        if !currentPair.isEmpty {
            if currentPair.count % 2 != 0 {
                // Count total non-empty lines for error message
                let totalNonEmpty = allLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                throw LyricsParseError.oddNumberOfLines(count: totalNonEmpty)
            }
            for i in stride(from: 0, to: currentPair.count, by: 2) {
                blocks.append(LyricBlock(
                    japanese: currentPair[i],
                    korean: currentPair[i + 1]
                ))
            }
        }

        if blocks.isEmpty {
            throw LyricsParseError.emptyInput
        }

        return blocks
    }
}
