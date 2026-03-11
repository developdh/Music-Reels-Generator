import Foundation

enum JapaneseTextNormalizer {
    /// Normalize Japanese text for fuzzy matching
    static func normalize(_ text: String) -> String {
        var result = text

        // Remove common punctuation and whitespace
        let punctuation: Set<Character> = [
            "。", "、", "！", "？", "「", "」", "『", "』",
            "（", "）", "…", "・", "　", ".", ",", "!", "?",
            "\"", "'", " ", "\t", "\n", "♪", "～", "〜",
            "(", ")", "[", "]", "【", "】", "―", "—", "-",
            "♫", "♩", "※", "×"
        ]
        result = String(result.filter { !punctuation.contains($0) })

        // Convert katakana to hiragana for uniform comparison
        result = katakanaToHiragana(result)

        // Normalize prolonged sound marks
        result = result.replacingOccurrences(of: "ー", with: "")
        result = result.replacingOccurrences(of: "〜", with: "")

        // Normalize full-width to half-width numbers
        let fullWidthDigits = "０１２３４５６７８９"
        let halfWidthDigits = "0123456789"
        for (fw, hw) in zip(fullWidthDigits, halfWidthDigits) {
            result = result.replacingOccurrences(of: String(fw), with: String(hw))
        }

        // Normalize full-width alphabets to half-width
        let fullWidthUpper = "ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ"
        let halfWidthUpper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for (fw, hw) in zip(fullWidthUpper, halfWidthUpper) {
            result = result.replacingOccurrences(of: String(fw), with: String(hw))
        }
        let fullWidthLower = "ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ"
        let halfWidthLower = "abcdefghijklmnopqrstuvwxyz"
        for (fw, hw) in zip(fullWidthLower, halfWidthLower) {
            result = result.replacingOccurrences(of: String(fw), with: String(hw))
        }

        return result.lowercased()
    }

    /// Convert katakana characters to hiragana
    private static func katakanaToHiragana(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            // Katakana range: U+30A1 to U+30F6 → Hiragana: U+3041 to U+3096
            if scalar.value >= 0x30A1 && scalar.value <= 0x30F6 {
                let hiragana = Unicode.Scalar(scalar.value - 0x60)!
                result.append(Character(hiragana))
            } else {
                result.append(Character(scalar))
            }
        }
        return result
    }

    /// Calculate similarity between two strings (0.0 to 1.0)
    static func similarity(_ a: String, _ b: String) -> Double {
        let na = normalize(a)
        let nb = normalize(b)

        if na.isEmpty && nb.isEmpty { return 1.0 }
        if na.isEmpty || nb.isEmpty { return 0.0 }

        // Use Levenshtein distance for overall similarity
        let distance = levenshteinDistance(na, nb)
        let maxLen = max(na.count, nb.count)
        let levenshteinSim = 1.0 - Double(distance) / Double(maxLen)

        // Also check substring containment for cases where whisper
        // transcribes a superset/subset of the lyric line
        let containmentSim = containmentScore(na, nb)

        return max(levenshteinSim, containmentSim)
    }

    /// Score based on how much of the shorter string is contained in the longer
    private static func containmentScore(_ a: String, _ b: String) -> Double {
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a

        if shorter.isEmpty { return 0 }

        // LCS-based containment
        let lcsLen = longestCommonSubsequenceLength(shorter, longer)
        let shorterCoverage = Double(lcsLen) / Double(shorter.count)
        let longerCoverage = Double(lcsLen) / Double(longer.count)

        // Weight toward shorter string coverage (lyric line fully matched)
        return shorterCoverage * 0.7 + longerCoverage * 0.3
    }

    /// Longest common subsequence length
    private static func longestCommonSubsequenceLength(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count
        if m == 0 || n == 0 { return 0 }

        // Space-optimized: only need previous row
        var prev = [Int](repeating: 0, count: n + 1)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    curr[j] = prev[j - 1] + 1
                } else {
                    curr[j] = max(prev[j], curr[j - 1])
                }
            }
            prev = curr
            curr = [Int](repeating: 0, count: n + 1)
        }
        return prev[n]
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

        // Space-optimized
        var prev = [Int](repeating: 0, count: n + 1)
        for j in 0...n { prev[j] = j }

        for i in 1...m {
            var curr = [Int](repeating: 0, count: n + 1)
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            prev = curr
        }
        return prev[n]
    }
}
