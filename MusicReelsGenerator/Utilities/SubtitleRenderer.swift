import AppKit
import CoreGraphics
import SwiftUI

/// Shared subtitle renderer used by both preview and export.
/// Renders subtitle images in the canonical 1080x1920 export canvas space
/// using Core Graphics, ensuring pixel-identical output.
enum SubtitleRenderer {

    /// Resolve a font by family name using NSFontDescriptor.
    static func resolveFont(family: String, size: Double) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family
        ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        if let font = NSFont(name: family, size: size) {
            return font
        }
        print("[SubtitleRenderer] WARNING: Could not resolve '\(family)', falling back to system font")
        return NSFont.systemFont(ofSize: size)
    }

    /// Render a single subtitle block as a CGImage at the canonical export canvas size.
    /// This is the single source of truth for subtitle appearance.
    static func renderBlock(
        _ block: LyricBlock,
        style: SubtitleStyle,
        canvasSize: CGSize
    ) -> CGImage? {
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)

        let fm = NSFontManager.shared
        var jaFont = resolveFont(family: style.japaneseFontFamily, size: style.japaneseFontSize)
        jaFont = fm.convert(jaFont, toHaveTrait: .boldFontMask)

        let koFont = resolveFont(family: style.koreanFontFamily, size: style.koreanFontSize)

        let textColor = NSColor(Color(hex: style.textColorHex))
        let outlineColor = NSColor(Color(hex: style.outlineColorHex))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let outlineR = max(style.outlineWidth, 1.0)
        let maxTextWidth = canvasSize.width - 60

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        guard NSGraphicsContext.current != nil else {
            image.unlockFocus()
            return nil
        }

        // Measure text
        let jaFillAttrs: [NSAttributedString.Key: Any] = [
            .font: jaFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        let koFillAttrs: [NSAttributedString.Key: Any] = [
            .font: koFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]

        let jaStr = NSAttributedString(string: block.japanese, attributes: jaFillAttrs)
        let koStr = NSAttributedString(string: block.korean, attributes: koFillAttrs)

        let jaSize = jaStr.boundingRect(
            with: NSSize(width: maxTextWidth, height: 500),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
        let koSize = koStr.boundingRect(
            with: NSSize(width: maxTextWidth, height: 500),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size

        // Y positions (NSImage origin = bottom-left)
        let koY = style.bottomMargin
        let jaY = koY + koSize.height + style.lineSpacing

        let koRect = NSRect(
            x: (canvasSize.width - maxTextWidth) / 2,
            y: koY,
            width: maxTextWidth, height: koSize.height + 10
        )
        let jaRect = NSRect(
            x: (canvasSize.width - maxTextWidth) / 2,
            y: jaY,
            width: maxTextWidth, height: jaSize.height + 10
        )

        // --- Outline pass ---
        let outlineJaAttrs: [NSAttributedString.Key: Any] = [
            .font: jaFont,
            .foregroundColor: outlineColor,
            .paragraphStyle: paragraphStyle
        ]
        let outlineKoAttrs: [NSAttributedString.Key: Any] = [
            .font: koFont,
            .foregroundColor: outlineColor,
            .paragraphStyle: paragraphStyle
        ]
        let outlineJaStr = NSAttributedString(string: block.japanese, attributes: outlineJaAttrs)
        let outlineKoStr = NSAttributedString(string: block.korean, attributes: outlineKoAttrs)

        let step: CGFloat = max(1.0, outlineR / 3.0)
        for dx in stride(from: -outlineR, through: outlineR, by: step) {
            for dy in stride(from: -outlineR, through: outlineR, by: step) {
                if dx * dx + dy * dy > outlineR * outlineR { continue }
                outlineJaStr.draw(in: jaRect.offsetBy(dx: dx, dy: dy))
                outlineKoStr.draw(in: koRect.offsetBy(dx: dx, dy: dy))
            }
        }

        // --- Shadow pass ---
        if style.shadowEnabled {
            let shadowJaAttrs: [NSAttributedString.Key: Any] = [
                .font: jaFont,
                .foregroundColor: NSColor(white: 0, alpha: 0.25),
                .paragraphStyle: paragraphStyle
            ]
            let shadowKoAttrs: [NSAttributedString.Key: Any] = [
                .font: koFont,
                .foregroundColor: NSColor(white: 0, alpha: 0.25),
                .paragraphStyle: paragraphStyle
            ]
            let off: CGFloat = 2
            NSAttributedString(string: block.japanese, attributes: shadowJaAttrs)
                .draw(in: jaRect.offsetBy(dx: off, dy: -off))
            NSAttributedString(string: block.korean, attributes: shadowKoAttrs)
                .draw(in: koRect.offsetBy(dx: off, dy: -off))
        }

        // --- Fill pass ---
        jaStr.draw(in: jaRect)
        koStr.draw(in: koRect)

        image.unlockFocus()

        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Render all timed blocks into a lookup table of CGImages.
    static func prerenderAll(
        blocks: [LyricBlock],
        style: SubtitleStyle,
        canvasSize: CGSize
    ) -> [UUID: CGImage] {
        var result: [UUID: CGImage] = [:]
        for block in blocks {
            guard block.hasTimingData else { continue }
            if let img = renderBlock(block, style: style, canvasSize: canvasSize) {
                result[block.id] = img
            }
        }
        return result
    }
}
