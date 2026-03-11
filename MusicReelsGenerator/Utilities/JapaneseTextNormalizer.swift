import Foundation

enum JapaneseTextNormalizer {
    /// Normalize Japanese text for fuzzy matching
    static func normalize(_ text: String) -> String {
        var result = text

        // Remove common punctuation
        let punctuation: [Character] = ["。", "、", "！", "？", "「", "」", "『", "』",
                                         "（", "）", "…", "・", "　", ".", ",", "!", "?",
                                         "\"", "'", " ", "\t"]
        result = String(result.filter { !punctuation.contains($0) })

        // Normalize prolonged sound marks (ー to nothing for matching)
        result = result.replacingOccurrences(of: "ー", with: "")

        // Normalize full-width to half-width numbers
        let fullWidthDigits = "０１２３４５６７８９"
        let halfWidthDigits = "0123456789"
        for (fw, hw) in zip(fullWidthDigits, halfWidthDigits) {
            result = result.replacingOccurrences(of: String(fw), with: String(hw))
        }

        return result.lowercased()
    }

    /// Calculate similarity between two strings (0.0 to 1.0)
    static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a)
        let nb = normalize(b)

        if na.isEmpty && nb.isEmpty { return 1.0 }
        if na.isEmpty || nb.isEmpty { return 0.0 }

        let distance = levenshteinDistance(na, nb)
        let maxLen = max(na.count, nb.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    /// Check if b contains a significant portion of a
    static func containsMatch(_ query: String, in text: String) -> Bool {
        let nq = normalize(query)
        let nt = normalize(text)
        if nq.isEmpty { return false }
        return nt.contains(nq)
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        return matrix[m][n]
    }
}
