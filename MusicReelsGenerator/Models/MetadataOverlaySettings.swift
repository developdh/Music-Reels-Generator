import Foundation

struct MetadataOverlaySettings: Codable, Equatable {
    var isEnabled: Bool = false
    var titleText: String = ""
    var artistText: String = ""

    // Title typography
    var titleFontFamily: String = "Helvetica Neue"
    var titleFontSize: Double = 42
    var titleTextColorHex: String = "#FFFFFF"

    // Artist typography
    var artistFontFamily: String = "Helvetica Neue"
    var artistFontSize: Double = 32
    var artistTextColorHex: String = "#CCCCCC"

    // Background box
    var backgroundColorHex: String = "#000000"
    var backgroundOpacity: Double = 0.6
    var cornerRadius: Double = 12
    var horizontalPadding: Double = 20
    var verticalPadding: Double = 14

    // Position (in canonical 1080x1920 space)
    var topMargin: Double = 80
    var leftMargin: Double = 40

    // Spacing between title and artist lines
    var lineSpacing: Double = 6

    var hasContent: Bool {
        !titleText.trimmingCharacters(in: .whitespaces).isEmpty ||
        !artistText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var shouldRender: Bool {
        isEnabled && hasContent
    }
}
