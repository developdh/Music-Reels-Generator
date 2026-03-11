import Foundation

enum ExportError: LocalizedError {
    case ffmpegNotFound
    case noVideoSource
    case noLyricTiming
    case exportFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Install with: brew install ffmpeg"
        case .noVideoSource:
            return "No source video file set."
        case .noLyricTiming:
            return "No lyrics with timing data. Run alignment or set times manually."
        case .exportFailed(let msg):
            return "Export failed: \(msg)"
        case .cancelled:
            return "Export was cancelled."
        }
    }
}

enum ExportState: Equatable {
    case idle
    case preparing
    case exporting(progress: Double)
    case completed(URL)
    case failed(String)
}

class ExportService {
    private var currentProcess: Process?

    func export(
        project: Project,
        outputURL: URL,
        onProgress: @escaping (ExportState) -> Void
    ) async throws {
        guard let ffmpeg = ProcessRunner.findFFmpeg() else {
            throw ExportError.ffmpegNotFound
        }

        guard let videoURL = project.sourceVideoURL else {
            throw ExportError.noVideoSource
        }

        let timedBlocks = project.lyricBlocks.filter { $0.hasTimingData }
        guard !timedBlocks.isEmpty else {
            throw ExportError.noLyricTiming
        }

        onProgress(.preparing)

        // Create temporary ASS subtitle file
        let tempDir = NSTemporaryDirectory()
        let assURL = URL(fileURLWithPath: tempDir + "lyrics_\(project.id.uuidString).ass")

        try SubtitleRenderService.writeASS(
            blocks: timedBlocks,
            style: project.subtitleStyle,
            to: assURL,
            videoWidth: project.cropSettings.outputWidth,
            videoHeight: project.cropSettings.outputHeight
        )

        // Build FFmpeg filter chain
        let crop = project.cropSettings
        let meta = project.videoMetadata

        // Calculate crop dimensions
        let sourceW = Double(meta.width)
        let sourceH = Double(meta.height)
        let targetRatio = Double(crop.outputWidth) / Double(crop.outputHeight)

        var filterParts: [String] = []

        if meta.isLandscape {
            // Landscape to portrait: crop width from center (+ offset)
            let cropH = sourceH
            let cropW = cropH * targetRatio
            let maxOffsetX = (sourceW - cropW) / 2.0
            let offsetX = sourceW / 2.0 - cropW / 2.0 + crop.horizontalOffset * maxOffsetX

            filterParts.append("crop=\(Int(cropW)):\(Int(cropH)):\(Int(max(0, offsetX))):0")
        } else {
            // Already portrait or square: just scale
            filterParts.append("crop=in_w:in_h:0:0")
        }

        // Scale to output resolution
        filterParts.append("scale=\(crop.outputWidth):\(crop.outputHeight):force_original_aspect_ratio=decrease")
        filterParts.append("pad=\(crop.outputWidth):\(crop.outputHeight):(ow-iw)/2:(oh-ih)/2:black")

        // Burn in subtitles
        let assPath = assURL.path.replacingOccurrences(of: "'", with: "'\\''")
            .replacingOccurrences(of: ":", with: "\\:")
        filterParts.append("ass='\(assPath)'")

        let filterChain = filterParts.joined(separator: ",")

        // Build FFmpeg command
        let args = [
            "-i", videoURL.path,
            "-vf", filterChain,
            "-c:v", "libx264",
            "-preset", "medium",
            "-crf", "20",
            "-c:a", "aac",
            "-b:a", "192k",
            "-r", "30",
            "-movflags", "+faststart",
            "-y",
            outputURL.path
        ]

        onProgress(.exporting(progress: 0.1))

        // Log the command for debugging
        let cmdString = "\(ffmpeg) \(args.joined(separator: " "))"
        print("FFmpeg command: \(cmdString)")

        let result = try await ProcessRunner.run(ffmpeg, arguments: args)

        // Clean up temp files
        try? FileManager.default.removeItem(at: assURL)

        guard result.succeeded else {
            let errorMsg = result.stderr.isEmpty ? "Unknown FFmpeg error" : result.stderr
            throw ExportError.exportFailed(errorMsg)
        }

        onProgress(.completed(outputURL))
    }

    func cancel() {
        currentProcess?.terminate()
    }
}
