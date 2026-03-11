import Foundation

struct Project: Codable, Identifiable {
    let id: UUID
    var title: String
    var sourceVideoPath: String?
    var videoMetadata: VideoMetadata
    var cropSettings: CropSettings
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

    mutating func touch() {
        updatedAt = Date()
    }
}
