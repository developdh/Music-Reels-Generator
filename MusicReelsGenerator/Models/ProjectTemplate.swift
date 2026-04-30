import Foundation

/// A reusable project template that bundles visual styling, language, and layout
/// preferences. Excludes anything tied to a specific source video (trim, zoom/offset,
/// ignore regions, lyrics, file path) so a template can be applied to any new project.
struct ProjectTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Style payload (reuses the same shape as StylePreset)
    var subtitleStyle: SubtitleStyle
    var overlayStyle: OverlayStyleSnapshot

    // Language preference
    var primaryLanguage: PrimaryLanguage

    // Layout preferences
    var cropMode: CropMode
    var horizontalBlurRadius: Double

    // Alignment preference
    var alignmentQualityMode: AlignmentQualityMode

    var version: Int

    static let currentVersion = 1

    init(
        id: UUID = UUID(),
        name: String,
        subtitleStyle: SubtitleStyle,
        overlayStyle: OverlayStyleSnapshot,
        primaryLanguage: PrimaryLanguage,
        cropMode: CropMode,
        horizontalBlurRadius: Double,
        alignmentQualityMode: AlignmentQualityMode,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.subtitleStyle = subtitleStyle
        self.overlayStyle = overlayStyle
        self.primaryLanguage = primaryLanguage
        self.cropMode = cropMode
        self.horizontalBlurRadius = horizontalBlurRadius
        self.alignmentQualityMode = alignmentQualityMode
        self.version = Self.currentVersion
    }

    /// Capture the current project's style + language + layout preferences as a template.
    static func fromProject(
        name: String,
        project: Project,
        alignmentQualityMode: AlignmentQualityMode
    ) -> ProjectTemplate {
        ProjectTemplate(
            name: name,
            subtitleStyle: project.subtitleStyle,
            overlayStyle: .from(project.metadataOverlay),
            primaryLanguage: project.primaryLanguage,
            cropMode: project.cropSettings.mode,
            horizontalBlurRadius: project.cropSettings.blurRadius,
            alignmentQualityMode: alignmentQualityMode
        )
    }

    // Backward-compatible decoding for forward field additions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        subtitleStyle = try c.decode(SubtitleStyle.self, forKey: .subtitleStyle)
        overlayStyle = try c.decode(OverlayStyleSnapshot.self, forKey: .overlayStyle)
        primaryLanguage = try c.decodeIfPresent(PrimaryLanguage.self, forKey: .primaryLanguage) ?? .japanese
        cropMode = try c.decodeIfPresent(CropMode.self, forKey: .cropMode) ?? .vertical
        horizontalBlurRadius = try c.decodeIfPresent(Double.self, forKey: .horizontalBlurRadius) ?? 20.0
        alignmentQualityMode = try c.decodeIfPresent(AlignmentQualityMode.self, forKey: .alignmentQualityMode) ?? .legacy
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    }
}

/// Container for serializing the full template library.
struct ProjectTemplateLibrary: Codable {
    var templates: [ProjectTemplate]
    var libraryVersion: Int = 1
}
