import Foundation

enum SubtitleRenderService {
    static func generateASS(
        blocks: [LyricBlock],
        style: SubtitleStyle,
        videoWidth: Int = 1080,
        videoHeight: Int = 1920
    ) -> String {
        let jaMarginV = Int(style.bottomMargin + style.koreanFontSize + style.lineSpacing)
        let koMarginV = Int(style.bottomMargin)
        let shadow = style.shadowEnabled ? 2 : 0
        let jaPrimaryColor = assColor(style.japaneseTextColorHex)
        let koPrimaryColor = assColor(style.koreanTextColorHex)
        let outlineColor = assColor(style.outlineColorHex)
        let outline = Int(style.outlineWidth)

        var ass = "[Script Info]\n"
        ass += "Title: Music Reels Lyrics\n"
        ass += "ScriptType: v4.00+\n"
        ass += "PlayResX: \(videoWidth)\n"
        ass += "PlayResY: \(videoHeight)\n"
        ass += "WrapStyle: 0\n\n"

        ass += "[V4+ Styles]\n"
        ass += "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"

        // Japanese style — bold
        ass += "Style: Japanese,\(style.japaneseFontFamily),\(Int(style.japaneseFontSize)),\(jaPrimaryColor),&H00000000,\(outlineColor),&H80000000,1,0,0,0,100,100,0,0,1,\(outline),\(shadow),2,20,20,\(jaMarginV),1\n"

        // Korean style — regular weight
        ass += "Style: Korean,\(style.koreanFontFamily),\(Int(style.koreanFontSize)),\(koPrimaryColor),&H00000000,\(outlineColor),&H80000000,0,0,0,0,100,100,0,0,1,\(outline),\(shadow),2,20,20,\(koMarginV),1\n"

        ass += "\n[Events]\n"
        ass += "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"

        for block in blocks {
            guard let start = block.startTime, let end = block.endTime else { continue }

            let startStr = TimeFormatter.assTimestamp(start)
            let endStr = TimeFormatter.assTimestamp(end)

            let jaText = escapeASS(block.japanese)
            ass += "Dialogue: 0,\(startStr),\(endStr),Japanese,,0,0,0,,\(jaText)\n"

            let koText = escapeASS(block.korean)
            ass += "Dialogue: 0,\(startStr),\(endStr),Korean,,0,0,0,,\(koText)\n"
        }

        return ass
    }

    /// Convert hex color to ASS format (&H00BBGGRR)
    private static func assColor(_ hex: String) -> String {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 else { return "&H00FFFFFF" }

        let r = String(clean.prefix(2))
        let g = String(clean.dropFirst(2).prefix(2))
        let b = String(clean.dropFirst(4).prefix(2))

        return "&H00\(b)\(g)\(r)"
    }

    private static func escapeASS(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
    }

    static func writeASS(
        blocks: [LyricBlock],
        style: SubtitleStyle,
        to url: URL,
        videoWidth: Int = 1080,
        videoHeight: Int = 1920
    ) throws {
        let content = generateASS(
            blocks: blocks,
            style: style,
            videoWidth: videoWidth,
            videoHeight: videoHeight
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
