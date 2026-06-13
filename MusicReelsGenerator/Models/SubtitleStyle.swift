import Foundation
import SwiftUI

struct SubtitleStyle: Equatable {
    var japaneseFontFamily: String = "Hiragino Sans"
    var koreanFontFamily: String = "Apple SD Gothic Neo"
    var japaneseFontSize: Double = 48
    var koreanFontSize: Double = 38
    var japaneseTextColorHex: String = "#FFFFFF"
    var koreanTextColorHex: String = "#FFFFFF"
    var outlineColorHex: String = "#000000"
    var outlineWidth: Double = 4.0
    var shadowEnabled: Bool = true
    var bottomMargin: Double = 200
    var lineSpacing: Double = 10
    // Background box / scrim behind the subtitle text (readability over busy video)
    var backgroundEnabled: Bool = false
    var backgroundColorHex: String = "#000000"
    var backgroundOpacity: Double = 0.5
    var backgroundCornerRadius: Double = 14
    var backgroundPaddingX: Double = 28
    var backgroundPaddingY: Double = 14

    var japaneseTextColor: Color {
        Color(hex: japaneseTextColorHex)
    }

    var backgroundColor: Color {
        Color(hex: backgroundColorHex)
    }

    var koreanTextColor: Color {
        Color(hex: koreanTextColorHex)
    }

    var outlineColor: Color {
        Color(hex: outlineColorHex)
    }
}

extension SubtitleStyle: Codable {
    enum CodingKeys: String, CodingKey {
        case japaneseFontFamily, koreanFontFamily
        case japaneseFontSize, koreanFontSize
        case japaneseTextColorHex, koreanTextColorHex
        case textColorHex // legacy single color
        case outlineColorHex, outlineWidth, shadowEnabled
        case bottomMargin, lineSpacing
        case backgroundEnabled, backgroundColorHex, backgroundOpacity
        case backgroundCornerRadius, backgroundPaddingX, backgroundPaddingY
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        japaneseFontFamily = try c.decodeIfPresent(String.self, forKey: .japaneseFontFamily) ?? "Hiragino Sans"
        koreanFontFamily = try c.decodeIfPresent(String.self, forKey: .koreanFontFamily) ?? "Apple SD Gothic Neo"
        japaneseFontSize = try c.decodeIfPresent(Double.self, forKey: .japaneseFontSize) ?? 48
        koreanFontSize = try c.decodeIfPresent(Double.self, forKey: .koreanFontSize) ?? 38
        outlineColorHex = try c.decodeIfPresent(String.self, forKey: .outlineColorHex) ?? "#000000"
        outlineWidth = try c.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 4.0
        shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? true
        bottomMargin = try c.decodeIfPresent(Double.self, forKey: .bottomMargin) ?? 200
        lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 10
        backgroundEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
        backgroundColorHex = try c.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? "#000000"
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.5
        backgroundCornerRadius = try c.decodeIfPresent(Double.self, forKey: .backgroundCornerRadius) ?? 14
        backgroundPaddingX = try c.decodeIfPresent(Double.self, forKey: .backgroundPaddingX) ?? 28
        backgroundPaddingY = try c.decodeIfPresent(Double.self, forKey: .backgroundPaddingY) ?? 14

        // Migration: if new per-language keys exist, use them; otherwise fall back to legacy single color
        if let jaHex = try c.decodeIfPresent(String.self, forKey: .japaneseTextColorHex) {
            japaneseTextColorHex = jaHex
            koreanTextColorHex = try c.decodeIfPresent(String.self, forKey: .koreanTextColorHex) ?? jaHex
        } else {
            let legacy = try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? "#FFFFFF"
            japaneseTextColorHex = legacy
            koreanTextColorHex = legacy
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(japaneseFontFamily, forKey: .japaneseFontFamily)
        try c.encode(koreanFontFamily, forKey: .koreanFontFamily)
        try c.encode(japaneseFontSize, forKey: .japaneseFontSize)
        try c.encode(koreanFontSize, forKey: .koreanFontSize)
        try c.encode(japaneseTextColorHex, forKey: .japaneseTextColorHex)
        try c.encode(koreanTextColorHex, forKey: .koreanTextColorHex)
        try c.encode(outlineColorHex, forKey: .outlineColorHex)
        try c.encode(outlineWidth, forKey: .outlineWidth)
        try c.encode(shadowEnabled, forKey: .shadowEnabled)
        try c.encode(bottomMargin, forKey: .bottomMargin)
        try c.encode(lineSpacing, forKey: .lineSpacing)
        try c.encode(backgroundEnabled, forKey: .backgroundEnabled)
        try c.encode(backgroundColorHex, forKey: .backgroundColorHex)
        try c.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try c.encode(backgroundCornerRadius, forKey: .backgroundCornerRadius)
        try c.encode(backgroundPaddingX, forKey: .backgroundPaddingX)
        try c.encode(backgroundPaddingY, forKey: .backgroundPaddingY)
    }
}
