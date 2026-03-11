import Foundation

struct Project: Codable, Identifiable {
    let id: UUID
    var title: String
    var sourceVideoPath: String?
    var videoMetadata: VideoMetadata
    var cropSettings: CropSettings
    var trimSettings: TrimSettings
    var subtitleStyle: SubtitleStyle
    var lyricBlocks: [LyricBlock]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Untitled Project"
    ) {
        self.id = id
        self.title = title
        self.sourceVideoPath = nil
        self.videoMetadata = VideoMetadata()
        self.cropSettings = CropSettings()
        self.trimSettings = TrimSettings()
        self.subtitleStyle = SubtitleStyle()
        self.lyricBlocks = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var sourceVideoURL: URL? {
        guard let path = sourceVideoPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var hasVideo: Bool {
        sourceVideoPath != nil
    }

    var hasLyrics: Bool {
        !lyricBlocks.isEmpty
    }

    var hasTimingData: Bool {
        lyricBlocks.contains { $0.hasTimingData }
    }

    var isReadyForExport: Bool {
        hasVideo && hasLyrics && hasTimingData
    }

    // Backward-compatible decoding (old files lack trimSettings)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        sourceVideoPath = try container.decodeIfPresent(String.self, forKey: .sourceVideoPath)
        videoMetadata = try container.decode(VideoMetadata.self, forKey: .videoMetadata)
        cropSettings = try container.decode(CropSettings.self, forKey: .cropSettings)
        trimSettings = try container.decodeIfPresent(TrimSettings.self, forKey: .trimSettings)
            ?? TrimSettings.fullDuration(videoMetadata.duration)
        subtitleStyle = try container.decode(SubtitleStyle.self, forKey: .subtitleStyle)
        lyricBlocks = try container.decode([LyricBlock].self, forKey: .lyricBlocks)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    mutating func touch() {
        updatedAt = Date()
    }
}
