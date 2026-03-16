import Foundation

enum LyricsParseError: LocalizedError {
    case emptyInput

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "No lyrics text provided."
        }
    }
}

enum LyricsParserService {
    /// Parse lyrics from a block format:
    /// - 1 line per block: primary language only (secondary = "")
    /// - 2 lines per block: primary + secondary language
    /// - Blocks separated by blank lines
    /// Mixing 1-line and 2-line blocks within the same input is allowed.
    static func parse(_ text: String) throws -> [LyricBlock] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LyricsParseError.emptyInput
        }

        let allLines = trimmed.components(separatedBy: .newlines)

        var blocks: [LyricBlock] = []
        var currentGroup: [String] = []

        func flushGroup(_ group: [String]) {
            var i = 0
            while i < group.count {
                if i + 1 < group.count {
                    // 2 lines available — treat as primary + secondary
                    blocks.append(LyricBlock(japanese: group[i], korean: group[i + 1]))
                    i += 2
                } else {
                    // 1 line — primary only
                    blocks.append(LyricBlock(japanese: group[i], korean: ""))
                    i += 1
                }
            }
        }

        for line in allLines {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty {
                if !currentGroup.isEmpty {
                    flushGroup(currentGroup)
                    currentGroup = []
                }
            } else {
                currentGroup.append(stripped)
            }
        }

        if !currentGroup.isEmpty {
            flushGroup(currentGroup)
        }

        if blocks.isEmpty {
            throw LyricsParseError.emptyInput
        }

        return blocks
    }
}
