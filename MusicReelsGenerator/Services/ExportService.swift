import Foundation
import AVFoundation
import CoreGraphics
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
        var trim = project.trimSettings
        // Safety: if trim end is 0 or invalid, use full duration
        if trim.endTime <= trim.startTime {
            trim = .fullDuration(project.videoMetadata.duration)
        }
        let outW = crop.outputWidth
        let outH = crop.outputHeight
        let meta = project.videoMetadata

        // --- Step 1: FFmpeg trim + crop/scale → intermediate file ---
        let tempDir = "/tmp/mreels_export"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let croppedURL = URL(fileURLWithPath: "\(tempDir)/cropped.mp4")
        try? FileManager.default.removeItem(at: croppedURL)

        let sourceW = Double(meta.width)
        let sourceH = Double(meta.height)
        let targetW = Double(outW)
        let targetH = Double(outH)

        let filterChain: String

        switch crop.mode {
        case .vertical:
            // 세로모드: scale-to-fill (cover) + crop with offset
            let zoom = crop.zoomScale
            let scaleFactor = max(targetW / sourceW, targetH / sourceH) * zoom
            let scaledW = Int((sourceW * scaleFactor).rounded(.up))
            let scaledH = Int((sourceH * scaleFactor).rounded(.up))
            let evenScaledW = scaledW + (scaledW % 2)
            let evenScaledH = scaledH + (scaledH % 2)
            let overflowX = Double(evenScaledW) - targetW
            let overflowY = Double(evenScaledH) - targetH
            let cropX = Int(((crop.horizontalOffset + 1.0) / 2.0 * overflowX).rounded())
            let cropY = Int(((crop.verticalOffset + 1.0) / 2.0 * overflowY).rounded())
            filterChain = "scale=\(evenScaledW):\(evenScaledH),crop=\(outW):\(outH):\(cropX):\(cropY)"

        case .horizontal:
            // 가로모드: blurred background + fitted foreground overlay
            let blurLuma = Int(crop.blurRadius)
            let blurChroma = max(blurLuma / 4, 1)
            let zoom = crop.zoomScale

            // Foreground: scale to fit inside canvas (preserve aspect ratio), apply zoom
            let fitScale = min(targetW / sourceW, targetH / sourceH) * zoom
            var fgW = Int((sourceW * fitScale).rounded())
            var fgH = Int((sourceH * fitScale).rounded())
            // Clamp to canvas
            fgW = min(fgW, outW)
            fgH = min(fgH, outH)
            // Even dimensions
            fgW += fgW % 2
            fgH += fgH % 2

            // Foreground vertical position from verticalOffset (-1..1)
            let maxOffsetY = Int(targetH) - fgH
            let overlayY = Int(((crop.verticalOffset + 1.0) / 2.0) * Double(maxOffsetY))
            let overlayX = (outW - fgW) / 2

            filterChain = """
            split=2[bg][fg];\
            [bg]scale=\(outW):\(outH):force_original_aspect_ratio=increase,\
            crop=\(outW):\(outH),boxblur=\(blurLuma):\(blurChroma)[bgblur];\
            [fg]scale=\(fgW):\(fgH)[fgfit];\
            [bgblur][fgfit]overlay=\(overlayX):\(overlayY)
            """
        }

        // Build FFmpeg args with trim via -ss (seek) and -t (duration)
        var ffmpegArgs: [String] = []
        ffmpegArgs += ["-ss", String(format: "%.3f", trim.startTime)]
        ffmpegArgs += ["-i", videoURL.path]
        ffmpegArgs += ["-t", String(format: "%.3f", trim.duration)]
        ffmpegArgs += [
            "-vf", filterChain,
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k",
            "-r", "30",
            "-movflags", "+faststart",
            "-y", croppedURL.path
        ]

        onProgress(.exporting(progress: 0.05))
        print("FFmpeg crop+trim: \(ffmpeg) \(ffmpegArgs.joined(separator: " "))")

        let cropResult = try await ProcessRunner.run(ffmpeg, arguments: ffmpegArgs)
        guard cropResult.succeeded else {
            throw ExportError.exportFailed(cropResult.stderr)
        }

        onProgress(.exporting(progress: 0.4))

        // --- Step 2: Burn subtitles frame-by-frame via AVAssetReader/Writer ---
        // Remap lyric timing: source-absolute → trim-relative (trimStart becomes 0)
        let exportBlocks = TrimTimingUtility.blocksForExport(timedBlocks, trim: trim)

        try? FileManager.default.removeItem(at: outputURL)

        try await burnSubtitlesFrameByFrame(
            inputURL: croppedURL,
            outputURL: outputURL,
            blocks: exportBlocks,
            style: project.subtitleStyle,
            metadataOverlay: project.metadataOverlay,
            outputSize: CGSize(width: outW, height: outH),
            onProgress: { p in
                onProgress(.exporting(progress: 0.4 + p * 0.6))
            }
        )

        try? FileManager.default.removeItem(at: croppedURL)
        onProgress(.completed(outputURL))
    }

    // MARK: - Frame-by-frame subtitle burn-in

    private func burnSubtitlesFrameByFrame(
        inputURL: URL,
        outputURL: URL,
        blocks: [LyricBlock],
        style: SubtitleStyle,
        metadataOverlay: MetadataOverlaySettings,
        outputSize: CGSize,
        onProgress: @escaping (Double) -> Void
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let totalSeconds = CMTimeGetSeconds(duration)

        // --- Reader ---
        let reader = try AVAssetReader(asset: asset)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.compositionFailed
        }

        let videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
        videoReaderOutput.alwaysCopiesSampleData = false
        reader.add(videoReaderOutput)

        var audioReaderOutput: AVAssetReaderTrackOutput?
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)
            audioReaderOutput = output
        }

        // --- Writer ---
        let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

        let videoWriterSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoWriterSettings)
        videoWriterInput.expectsMediaDataInRealTime = false

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )
        writer.add(videoWriterInput)

        var audioWriterInput: AVAssetWriterInput?
        if audioReaderOutput != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioWriterInput = input
        }

        // --- Pre-render subtitle images using shared renderer ---
        let subtitleImages = SubtitleRenderer.prerenderAll(
            blocks: blocks, style: style, canvasSize: outputSize
        )

        // --- Pre-render metadata overlay (static, same for every frame) ---
        let metadataImage = SubtitleRenderer.renderMetadataOverlay(
            metadataOverlay, canvasSize: outputSize
        )

        // --- Process ---
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Write audio on a background queue
        let audioDone = DispatchSemaphore(value: 0)
        if let audioInput = audioWriterInput, let audioOutput = audioReaderOutput {
            let audioQueue = DispatchQueue(label: "audio.writer")
            audioInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioInput.isReadyForMoreMediaData {
                    if let sample = audioOutput.copyNextSampleBuffer() {
                        audioInput.append(sample)
                    } else {
                        audioInput.markAsFinished()
                        audioDone.signal()
                        return
                    }
                }
            }
        } else {
            audioDone.signal()
        }

        // Write video with subtitle overlay
        let width = Int(outputSize.width)
        let height = Int(outputSize.height)

        while reader.status == .reading {
            if !videoWriterInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                continue
            }

            guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                break
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let timeSec = CMTimeGetSeconds(presentationTime)

            // Find active subtitle block
            let activeBlock = blocks.first { b in
                guard let s = b.startTime, let e = b.endTime else { return false }
                return timeSec >= s && timeSec < e
            }

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

            let subtitleImage = activeBlock.flatMap { subtitleImages[$0.id] }
            let needsOverlay = subtitleImage != nil || metadataImage != nil

            if needsOverlay {
                let newBuffer = drawOverlays(
                    onto: imageBuffer, width: width, height: height,
                    pool: pixelBufferAdaptor.pixelBufferPool,
                    metadataImage: metadataImage,
                    subtitleImage: subtitleImage
                )
                pixelBufferAdaptor.append(newBuffer ?? imageBuffer, withPresentationTime: presentationTime)
            } else {
                pixelBufferAdaptor.append(imageBuffer, withPresentationTime: presentationTime)
            }

            // Progress
            if totalSeconds > 0 {
                let p = timeSec / totalSeconds
                await MainActor.run { onProgress(p) }
            }
        }

        videoWriterInput.markAsFinished()
        audioDone.wait()

        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Writer failed")
        }
        if reader.status == .failed {
            throw ExportError.exportFailed(reader.error?.localizedDescription ?? "Reader failed")
        }
    }

    // MARK: - Composite overlays onto video frame

    private func drawOverlays(
        onto pixelBuffer: CVPixelBuffer,
        width: Int, height: Int,
        pool: CVPixelBufferPool?,
        metadataImage: CGImage?,
        subtitleImage: CGImage?
    ) -> CVPixelBuffer? {
        var newBuffer: CVPixelBuffer?

        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &newBuffer)
        }
        guard let outputBuffer = newBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(outputBuffer, [])

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(outputBuffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(outputBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(outputBuffer, [])
            return nil
        }

        // Draw original frame
        if let srcCtx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let frameImage = srcCtx.makeImage() {
            ctx.draw(frameImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        let frameRect = CGRect(x: 0, y: 0, width: width, height: height)

        // Draw metadata overlay (top-left title/artist)
        if let metadataImage {
            ctx.draw(metadataImage, in: frameRect)
        }

        // Draw subtitle overlay (bottom lyrics)
        if let subtitleImage {
            ctx.draw(subtitleImage, in: frameRect)
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(outputBuffer, [])

        return outputBuffer
    }

    func cancel() {}
}
