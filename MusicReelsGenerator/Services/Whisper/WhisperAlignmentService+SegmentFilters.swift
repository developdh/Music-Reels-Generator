import Foundation

extension WhisperAlignmentService {
    /// Merge very short consecutive segments into longer ones.
    /// Never merge across non-speech segments (instrumentals/applause).
    static func mergeFragments(_ segments: [WhisperSegment], minDuration: Double) -> [WhisperSegment] {
        guard !segments.isEmpty else { return segments }

        var merged: [WhisperSegment] = []
        var current = segments[0]

        for i in 1..<segments.count {
            let next = segments[i]
            let currentDuration = current.endTime - current.startTime

            // Never merge speech with non-speech segments
            let currentIsNonSpeech = isNonSpeechSegment(current)
            let nextIsNonSpeech = isNonSpeechSegment(next)

            // Merge if current segment is very short and next is close, and both are same type
            if currentDuration < minDuration && (next.startTime - current.endTime) < 0.5
                && currentIsNonSpeech == nextIsNonSpeech {
                let mergedConfidence: Double?
                switch (current.confidence, next.confidence) {
                case let (a?, b?): mergedConfidence = (a + b) / 2.0
                case let (a?, nil): mergedConfidence = a
                case let (nil, b?): mergedConfidence = b
                case (nil, nil):    mergedConfidence = nil
                }
                current = WhisperSegment(
                    startTime: current.startTime,
                    endTime: next.endTime,
                    text: current.text + next.text,
                    confidence: mergedConfidence
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    /// Check if a whisper segment is a non-speech marker (applause, music, etc.)
    /// Whisper often produces segments like (拍手), (音楽), [Music], [Applause], etc.
    /// for instrumental/non-vocal sections.
    static func isNonSpeechSegment(_ segment: WhisperSegment) -> Bool {
        let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Detect markers in parentheses or brackets: (拍手), [Music], etc.
        if (text.hasPrefix("(") && text.hasSuffix(")")) ||
           (text.hasPrefix("[") && text.hasSuffix("]")) ||
           (text.hasPrefix("（") && text.hasSuffix("）")) {
            return true
        }
        // Common non-speech markers
        let nonSpeechPatterns = ["拍手", "音楽", "歓声", "ため息", "笑い", "笑",
                                  "掌声", "音乐", "笑声", "叹息",
                                  "music", "applause", "laughter", "silence"]
        let lower = text.lowercased()
        for pattern in nonSpeechPatterns {
            if lower.contains(pattern.lowercased()) { return true }
        }
        return false
    }
}
