import Foundation

extension WhisperAlignmentService {
    static func printAlignmentReport(_ blocks: [LyricBlock]) {
        print("\n=== ALIGNMENT REPORT ===")
        var gapCount = 0
        var totalGapDuration = 0.0
        for (i, block) in blocks.enumerated() {
            let conf = block.confidence ?? 0
            let flag: String
            if block.isManuallyAdjusted { flag = "MANUAL" }
            else if block.isAnchor { flag = "ANCHOR" }
            else if conf < 0.1 { flag = "INTERP" }
            else if conf < 0.4 { flag = "  WEAK" }
            else { flag = "    OK" }

            let timeStr: String
            if let s = block.startTime, let e = block.endTime {
                timeStr = String(format: "%6.2f–%6.2f", s, e)
            } else {
                timeStr = "   -.--–   -.--"
            }

            // Detect gap from previous block
            if i > 0, let prevEnd = blocks[i - 1].endTime, let curStart = block.startTime {
                let gap = curStart - prevEnd
                if gap > 0.5 {
                    gapCount += 1
                    totalGapDuration += gap
                    print(String(format: "     ⏸ GAP %.2fs (no subtitle)", gap))
                }
            }

            let jaPreview = String(block.japanese.prefix(20))
            print(String(format: "[%2d] %@ conf=%.2f %@ %@", i, flag, conf, timeStr, jaPreview))
        }
        if gapCount > 0 {
            print(String(format: "[Alignment] %d gap(s) detected (total %.1fs of no-subtitle time)", gapCount, totalGapDuration))
        }
        print("=== END REPORT ===\n")

        // Also write report to a file for debugging
        var reportLines: [String] = ["=== ALIGNMENT REPORT ==="]
        for (i, block) in blocks.enumerated() {
            let conf = block.confidence ?? 0
            let flag: String
            if block.isManuallyAdjusted { flag = "MANUAL" }
            else if block.isAnchor { flag = "ANCHOR" }
            else if conf < 0.1 { flag = "INTERP" }
            else if conf < 0.4 { flag = "  WEAK" }
            else { flag = "    OK" }
            let timeStr: String
            if let s = block.startTime, let e = block.endTime {
                timeStr = String(format: "%6.2f–%6.2f (dur=%.2f)", s, e, e - s)
            } else {
                timeStr = "   -.--–   -.-- (no timing)"
            }
            if i > 0, let prevEnd = blocks[i - 1].endTime, let curStart = block.startTime {
                let gap = curStart - prevEnd
                if gap > 0.5 {
                    reportLines.append(String(format: "     ⏸ GAP %.2fs (no subtitle)", gap))
                } else if gap < -0.01 {
                    reportLines.append(String(format: "     ⚠ OVERLAP %.2fs", -gap))
                }
            }
            let jaPreview = String(block.japanese.prefix(30))
            reportLines.append(String(format: "[%2d] %@ conf=%.2f %@ %@", i, flag, conf, timeStr, jaPreview))
        }
        reportLines.append("=== END REPORT ===")
        let reportText = reportLines.joined(separator: "\n")
        try? reportText.write(toFile: "/tmp/mreels_alignment_report.txt", atomically: true, encoding: .utf8)
    }
}
