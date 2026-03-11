import Foundation
import SwiftUI

struct SubtitleStyle: Codable, Equatable {
    var japaneseFontFamily: String = "Hiragino Sans"
    var koreanFontFamily: String = "Apple SD Gothic Neo"
    var japaneseFontSize: Double = 48
    var koreanFontSize: Double = 38
    var textColorHex: String = "#FFFFFF"
    var outlineColorHex: String = "#000000"
    var outlineWidth: Double = 4.0
    var shadowEnabled: Bool = true
    var bottomMargin: Double = 200
    var lineSpacing: Double = 10

    var textColor: Color {
        Color(hex: textColorHex)
    }

    var outlineColor: Color {
        Color(hex: outlineColorHex)
    }
}
