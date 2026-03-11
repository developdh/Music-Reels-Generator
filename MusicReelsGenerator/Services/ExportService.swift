import Foundation
import AVFoundation
import CoreImage
import AppKit
import SwiftUI

enum ExportError: LocalizedError {
    case ffmpegNotFound
    case noVideoSource
    case noLyricTiming
    case exportFailed(String)
    case cancelled
    case compositionFailed

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
        case .compositionFailed:
            return "Failed to create video composition."
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
    /// Two-step export:
    /// 1. FFmpeg: scale-to-fill + crop → intermediate MP4 (no subtitles)
    /// 2. AVFoundation: overlay subtitle CALayers → final MP4
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

        let crop = project.cropSettings
        let outW = crop.outputWidth
        let outH = crop.outputHeight
        let meta = project.videoMetadata

        // --- Step 1: FFmpeg crop/scale ---
        let tempDir = "/tmp/mreels_export"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let croppedURL = URL(fileURLWithPath: "\(tempDir)/cropped.mp4")
        try? FileManager.default.removeItem(at: croppedURL)

        let sourceW = Double(meta.width)
        let sourceH = Double(meta.height)
        let targetW = Double(outW)
        let targetH = Double(outH)
        let scaleFactor = max(targetW / sourceW, targetH / sourceH)
        let scaledW = Int((sourceW * scaleFactor).rounded(.up))
        let scaledH = Int((sourceH * scaleFactor).rounded(.up))
        let evenScaledW = scaledW + (scaledW % 2)
        let evenScaledH = scaledH + (scaledH % 2)
        let overflowX = Double(evenScaledW) - targetW
        let overflowY = Double(evenScaledH) - targetH
        let cropX = Int(((crop.horizontalOffset + 1.0) / 2.0 * overflowX).rounded())
        let cropY = Int(((crop.verticalOffset + 1.0) / 2.0 * overflowY).rounded())

        let filterChain = "scale=\(evenScaledW):\(evenScaledH),crop=\(outW):\(outH):\(cropX):\(cropY)"

        let ffmpegArgs = [
            "-i", videoURL.path,
            "-vf", filterChain,
            "-c:v", "libx264",
            "-preset", "fast",
            "-crf", "18",
            "-c:a", "aac",
            "-b:a", "192k",
            "-r", "30",
            "-movflags", "+faststart",
            "-y",
            croppedURL.path
        ]

        onProgress(.exporting(progress: 0.1))
        print("FFmpeg crop command: \(ffmpeg) \(ffmpegArgs.joined(separator: " "))")

        let cropResult = try await ProcessRunner.run(ffmpeg, arguments: ffmpegArgs)
        guard cropResult.succeeded else {
            throw ExportError.exportFailed(cropResult.stderr)
        }

        onProgress(.exporting(progress: 0.5))

        // --- Step 2: Burn subtitles via AVFoundation + CALayer ---
        try await burnSubtitles(
            inputURL: croppedURL,
            outputURL: outputURL,
            blocks: timedBlocks,
            style: project.subtitleStyle,
            outputSize: CGSize(width: outW, height: outH),
            onProgress: { p in
                onProgress(.exporting(progress: 0.5 + p * 0.5))
            }
        )

        // Cleanup
        try? FileManager.default.removeItem(at: croppedURL)

        onProgress(.completed(outputURL))
    }

    private func burnSubtitles(
        inputURL: URL,
        outputURL: URL,
        blocks: [LyricBlock],
        style: SubtitleStyle,
        outputSize: CGSize,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)

        let composition = AVMutableComposition()

        // Add video track
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw ExportError.compositionFailed
        }
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.compositionFailed
        }
        try compVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        // Add audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let sourceAudioTrack = audioTracks.first,
           let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try compAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        // Build CALayer-based subtitle overlay
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: outputSize)

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: outputSize)
        overlayLayer.isGeometryFlipped = true

        // Add subtitle layers for each block
        for block in blocks {
            guard let startTime = block.startTime, let endTime = block.endTime else { continue }

            let subtitleLayer = makeSubtitleLayer(
                block: block,
                style: style,
                canvasSize: outputSize
            )

            // Animate: hidden → visible → hidden
            let showAnim = CABasicAnimation(keyPath: "opacity")
            showAnim.fromValue = 0.0
            showAnim.toValue = 1.0
            showAnim.beginTime = AVCoreAnimationBeginTimeAtZero + startTime
            showAnim.duration = 0.001
            showAnim.fillMode = .forwards
            showAnim.isRemovedOnCompletion = false

            let hideAnim = CABasicAnimation(keyPath: "opacity")
            hideAnim.fromValue = 1.0
            hideAnim.toValue = 0.0
            hideAnim.beginTime = AVCoreAnimationBeginTimeAtZero + endTime
            hideAnim.duration = 0.001
            hideAnim.fillMode = .forwards
            hideAnim.isRemovedOnCompletion = false

            subtitleLayer.opacity = 0
            subtitleLayer.add(showAnim, forKey: "show")
            subtitleLayer.add(hideAnim, forKey: "hide")

            overlayLayer.addSublayer(subtitleLayer)
        }

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: outputSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)

        // Create video composition with animation tool
        let videoComp = AVMutableVideoComposition()
        videoComp.renderSize = outputSize
        videoComp.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComp.instructions = [instruction]

        videoComp.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // Export
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.compositionFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComp

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return
        case .failed:
            throw ExportError.exportFailed(
                exportSession.error?.localizedDescription ?? "Unknown export error"
            )
        case .cancelled:
            throw ExportError.cancelled
        default:
            throw ExportError.exportFailed("Export ended with status: \(exportSession.status.rawValue)")
        }
    }

    /// Create a CALayer containing the bilingual subtitle for one block
    private func makeSubtitleLayer(
        block: LyricBlock,
        style: SubtitleStyle,
        canvasSize: CGSize
    ) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: canvasSize)

        let jaFont = NSFont(name: style.japaneseFontFamily, size: style.japaneseFontSize)
            ?? NSFont.boldSystemFont(ofSize: style.japaneseFontSize)
        let koFont = NSFont(name: style.koreanFontFamily, size: style.koreanFontSize)
            ?? NSFont.systemFont(ofSize: style.koreanFontSize)

        let textColor = NSColor(Color(hex: style.textColorHex))
        let outlineColor = NSColor(Color(hex: style.outlineColorHex))

        // Japanese text layer
        let jaLayer = makeTextLayer(
            text: block.japanese,
            font: jaFont,
            textColor: textColor,
            outlineColor: outlineColor,
            outlineWidth: style.outlineWidth,
            canvasWidth: canvasSize.width
        )

        // Korean text layer
        let koLayer = makeTextLayer(
            text: block.korean,
            font: koFont,
            textColor: textColor,
            outlineColor: outlineColor,
            outlineWidth: style.outlineWidth,
            canvasWidth: canvasSize.width
        )

        // Position: bottom-aligned with margins
        let koY = style.bottomMargin
        let jaY = koY + koLayer.frame.height + style.lineSpacing

        koLayer.frame.origin = CGPoint(
            x: (canvasSize.width - koLayer.frame.width) / 2,
            y: koY
        )
        jaLayer.frame.origin = CGPoint(
            x: (canvasSize.width - jaLayer.frame.width) / 2,
            y: jaY
        )

        container.addSublayer(jaLayer)
        container.addSublayer(koLayer)

        return container
    }

    private func makeTextLayer(
        text: String,
        font: NSFont,
        textColor: NSColor,
        outlineColor: NSColor,
        outlineWidth: Double,
        canvasWidth: CGFloat
    ) -> CATextLayer {
        let layer = CATextLayer()

        let style = NSMutableParagraphStyle()
        style.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .strokeColor: outlineColor,
            .strokeWidth: -(outlineWidth * 2), // Negative = fill + stroke
            .paragraphStyle: style
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        layer.string = attrString
        layer.isWrapped = true
        layer.alignmentMode = .center
        layer.contentsScale = 2.0

        // Calculate size
        let maxWidth = canvasWidth - 40
        let boundingRect = attrString.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        layer.frame = CGRect(
            x: 0, y: 0,
            width: min(boundingRect.width + 20, canvasWidth),
            height: boundingRect.height + 10
        )

        // Shadow
        layer.shadowColor = outlineColor.cgColor
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.8
        layer.shadowOffset = CGSize(width: 0, height: -2)

        return layer
    }

    func cancel() {
        // TODO: cancel support for AVAssetExportSession
    }
}
