import Foundation

enum SubtitleRenderService {
    /// Generate ASS subtitle file content from lyric blocks and style settings
    static func generateASS(
        blocks: [LyricBlock],
        style: SubtitleStyle,
        videoWidth: Int = 1080,
        videoHeight: Int = 1920
    ) -> String {
        var ass = """
        [Script Info]
        Title: Music Reels Lyrics
        ScriptType: v4.00+
        PlayResX: \(videoWidth)
        PlayResY: \(videoHeight)
        WrapStyle: 0

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Japanese,Hiragino Sans,\(Int(style.japaneseFontSize)),\(assColor(style.textColorHex)),&H00000000,\(assColor(style.outlineColorHex)),&H80000000,1,0,0,0,100,100,0,0,1,\(Int(style.outlineWidth)),\(style.shadowEnabled ? 2 : 0),2,20,20,\(Int(style.bottomMargin + style.koreanFontSize + style.lineSpacing)),0
        Style: Korean,Apple SD Gothic Neo,\(Int(style.koreanFontSize)),\(assColor(style.textColorHex)),&H00000000,\(assColor(style.outlineColorHex)),&H80000000,0,0,0,0,100,100,0,0,1,\(Int(style.outlineWidth)),\(style.shadowEnabled ? 2 : 0),2,20,20,\(Int(style.bottomMargin)),0

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

        """

        for block in blocks {
            guard let start = block.startTime, let end = block.endTime else { continue }

            let startStr = TimeFormatter.assTimestamp(start)
            let endStr = TimeFormatter.assTimestamp(end)

            // Japanese line
            let jaText = escapeASS(block.japanese)
            ass += "Dialogue: 0,\(startStr),\(endStr),Japanese,,0,0,0,,\(jaText)\n"

            // Korean line
            let koText = escapeASS(block.korean)
            ass += "Dialogue: 0,\(startStr),\(endStr),Korean,,0,0,0,,\(koText)\n"
        }

        return ass
    }

    /// Convert hex color to ASS format (&HAABBGGRR)
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

    /// Write ASS file to disk
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
