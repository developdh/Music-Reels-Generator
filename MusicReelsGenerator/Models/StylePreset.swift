import Foundation

/// A snapshot of the title/artist overlay visual style, excluding song-specific text content.
/// Used inside StylePreset to save reusable overlay styling without carrying actual title/artist text.
struct OverlayStyleSnapshot: Codable, Equatable {
    // Title typography
    var titleFontFamily: String
    var titleFontSize: Double
    var titleTextColorHex: String

    // Artist typography
    var artistFontFamily: String
    var artistFontSize: Double
    var artistTextColorHex: String

    // Background box
    var backgroundColorHex: String
    var backgroundOpacity: Double
    var cornerRadius: Double
    var horizontalPadding: Double
    var verticalPadding: Double

    // Position
    var topMargin: Double
    var leftMargin: Double

    // Spacing
    var lineSpacing: Double

    /// Create a snapshot from the current MetadataOverlaySettings (style fields only).
    static func from(_ settings: MetadataOverlaySettings) -> OverlayStyleSnapshot {
        OverlayStyleSnapshot(
            titleFontFamily: settings.titleFontFamily,
            titleFontSize: settings.titleFontSize,
            titleTextColorHex: settings.titleTextColorHex,
            artistFontFamily: settings.artistFontFamily,
            artistFontSize: settings.artistFontSize,
            artistTextColorHex: settings.artistTextColorHex,
            backgroundColorHex: settings.backgroundColorHex,
            backgroundOpacity: settings.backgroundOpacity,
            cornerRadius: settings.cornerRadius,
            horizontalPadding: settings.horizontalPadding,
            verticalPadding: settings.verticalPadding,
            topMargin: settings.topMargin,
            leftMargin: settings.leftMargin,
            lineSpacing: settings.lineSpacing
        )
    }

    /// Apply this snapshot's style values onto a MetadataOverlaySettings,
    /// preserving its isEnabled, titleText, and artistText.
    func apply(to settings: inout MetadataOverlaySettings) {
        settings.titleFontFamily = titleFontFamily
        settings.titleFontSize = titleFontSize
        settings.titleTextColorHex = titleTextColorHex
        settings.artistFontFamily = artistFontFamily
        settings.artistFontSize = artistFontSize
        settings.artistTextColorHex = artistTextColorHex
        settings.backgroundColorHex = backgroundColorHex
        settings.backgroundOpacity = backgroundOpacity
        settings.cornerRadius = cornerRadius
        settings.horizontalPadding = horizontalPadding
        settings.verticalPadding = verticalPadding
        settings.topMargin = topMargin
        settings.leftMargin = leftMargin
        settings.lineSpacing = lineSpacing
    }
}

/// A reusable style preset that captures visual styling for subtitles and overlays.
/// Does NOT contain song-specific data (title text, artist text, timing, alignment).
struct StylePreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var subtitleStyle: SubtitleStyle
    var overlayStyle: OverlayStyleSnapshot
    var version: Int

    static let currentVersion = 1

    init(
        id: UUID = UUID(),
        name: String,
        subtitleStyle: SubtitleStyle,
        overlayStyle: OverlayStyleSnapshot,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.subtitleStyle = subtitleStyle
        self.overlayStyle = overlayStyle
        self.version = Self.currentVersion
    }

    /// Create a preset from the current project's style settings.
    static func fromProject(
        name: String,
        subtitleStyle: SubtitleStyle,
        metadataOverlay: MetadataOverlaySettings
    ) -> StylePreset {
        StylePreset(
            name: name,
            subtitleStyle: subtitleStyle,
            overlayStyle: .from(metadataOverlay)
        )
    }
}

/// Container for serializing the full preset library.
struct StylePresetLibrary: Codable {
    var presets: [StylePreset]
    var libraryVersion: Int = 1
}
