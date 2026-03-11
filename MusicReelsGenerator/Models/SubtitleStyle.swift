import Foundation
import SwiftUI

struct SubtitleStyle: Codable, Equatable {
    var japaneseFontSize: Double = 42
    var koreanFontSize: Double = 36
    var textColorHex: String = "#FFFFFF"
    var outlineColorHex: String = "#000000"
    var outlineWidth: Double = 3.0
    var shadowEnabled: Bool = true
    var bottomMargin: Double = 200
    var lineSpacing: Double = 8

    var textColor: Color {
        Color(hex: textColorHex)
    }

    var outlineColor: Color {
        Color(hex: outlineColorHex)
    }
}
