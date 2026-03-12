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

        let jaTextColor = NSColor(Color(hex: style.japaneseTextColorHex))
        let koTextColor = NSColor(Color(hex: style.koreanTextColorHex))
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
            .foregroundColor: jaTextColor,
            .paragraphStyle: paragraphStyle
        ]
        let koFillAttrs: [NSAttributedString.Key: Any] = [
            .font: koFont,
            .foregroundColor: koTextColor,
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

    // MARK: - Metadata Overlay (top-left title/artist)

    /// Render the metadata overlay as a CGImage at the canonical export canvas size.
    /// Shows title and artist with a dark rounded background box.
    static func renderMetadataOverlay(
        _ settings: MetadataOverlaySettings,
        canvasSize: CGSize
    ) -> CGImage? {
        guard settings.shouldRender else { return nil }

        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)

        let titleText = settings.titleText.trimmingCharacters(in: .whitespaces)
        let artistText = settings.artistText.trimmingCharacters(in: .whitespaces)
        let hasTitle = !titleText.isEmpty
        let hasArtist = !artistText.isEmpty

        // Fonts
        let titleFont = resolveFont(family: settings.titleFontFamily, size: settings.titleFontSize)
        let artistFont = resolveFont(family: settings.artistFontFamily, size: settings.artistFontSize)

        // Colors
        let titleColor = NSColor(Color(hex: settings.titleTextColorHex))
        let artistColor = NSColor(Color(hex: settings.artistTextColorHex))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byTruncatingTail

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: titleColor,
            .paragraphStyle: paragraphStyle
        ]
        let artistAttrs: [NSAttributedString.Key: Any] = [
            .font: artistFont,
            .foregroundColor: artistColor,
            .paragraphStyle: paragraphStyle
        ]

        // Max text width — leave some space from right edge
        let maxTextWidth = canvasSize.width - settings.leftMargin - settings.horizontalPadding * 2 - 40

        // Measure text
        var titleSize = CGSize.zero
        var artistSize = CGSize.zero

        if hasTitle {
            let titleStr = NSAttributedString(string: titleText, attributes: titleAttrs)
            titleSize = titleStr.boundingRect(
                with: NSSize(width: maxTextWidth, height: 300),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
        }
        if hasArtist {
            let artistStr = NSAttributedString(string: artistText, attributes: artistAttrs)
            artistSize = artistStr.boundingRect(
                with: NSSize(width: maxTextWidth, height: 300),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
        }

        // Calculate box dimensions
        let contentWidth = max(titleSize.width, artistSize.width)
        let spacing = (hasTitle && hasArtist) ? settings.lineSpacing : 0
        let contentHeight = titleSize.height + spacing + artistSize.height

        let boxWidth = contentWidth + settings.horizontalPadding * 2
        let boxHeight = contentHeight + settings.verticalPadding * 2

        // NSImage origin is bottom-left; top-left in screen = bottom-left transform
        // Y position: canvas height - topMargin - boxHeight
        let boxX = settings.leftMargin
        let boxY = CGFloat(height) - settings.topMargin - boxHeight

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }

        // --- Draw background box ---
        let bgColor = NSColor(Color(hex: settings.backgroundColorHex))
            .withAlphaComponent(settings.backgroundOpacity)
        let boxRect = NSRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: settings.cornerRadius, yRadius: settings.cornerRadius)
        bgColor.setFill()
        boxPath.fill()

        // --- Draw text ---
        // Title at top of box, artist below
        // In NSImage coords: title goes higher (larger Y), artist below
        let textX = boxX + settings.horizontalPadding

        if hasArtist {
            let artistY = boxY + settings.verticalPadding
            let artistRect = NSRect(x: textX, y: artistY, width: maxTextWidth, height: artistSize.height + 4)
            NSAttributedString(string: artistText, attributes: artistAttrs).draw(in: artistRect)
        }

        if hasTitle {
            let titleY = boxY + settings.verticalPadding + (hasArtist ? artistSize.height + spacing : 0)
            let titleRect = NSRect(x: textX, y: titleY, width: maxTextWidth, height: titleSize.height + 4)
            NSAttributedString(string: titleText, attributes: titleAttrs).draw(in: titleRect)
        }

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
