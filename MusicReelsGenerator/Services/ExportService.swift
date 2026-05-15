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
        // Safety: empty or invalid trim → full source
        if trim.ranges.isEmpty || trim.duration <= 0 {
            trim = .fullDuration(project.videoMetadata.duration)
        }
        let outW = crop.outputWidth
        let outH = crop.outputHeight
        let meta = project.videoMetadata

        let filterChain = buildCropFilterChain(crop: crop, meta: meta, outW: outW, outH: outH)

        // --- Step 1: FFmpeg trim + crop/scale per range → concat into intermediate file ---
        let tempDir = "/tmp/mreels_export"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let croppedURL = URL(fileURLWithPath: "\(tempDir)/cropped.mp4")
        try? FileManager.default.removeItem(at: croppedURL)

        let sortedRanges = trim.sortedRanges

        if sortedRanges.count == 1 {
            // Single-range fast path: one FFmpeg pass directly to the cropped intermediate.
            try await runTrimCrop(
                ffmpeg: ffmpeg,
                inputURL: videoURL,
                range: sortedRanges[0],
                filterChain: filterChain,
                outputURL: croppedURL
            )
        } else {
            // Multi-range: encode each segment separately, then either concat (no re-encode)
            // or chain xfade/acrossfade transitions when a crossfade duration is set.
            var segmentURLs: [URL] = []
            for (i, range) in sortedRanges.enumerated() {
                let segURL = URL(fileURLWithPath: "\(tempDir)/seg_\(i).mp4")
                try? FileManager.default.removeItem(at: segURL)
                let segProgress = 0.05 + Double(i) / Double(sortedRanges.count) * 0.30
                onProgress(.exporting(progress: segProgress))
                try await runTrimCrop(
                    ffmpeg: ffmpeg,
                    inputURL: videoURL,
                    range: range,
                    filterChain: filterChain,
                    outputURL: segURL
                )
                segmentURLs.append(segURL)
            }

            onProgress(.exporting(progress: 0.36))
            let xfade = trim.effectiveCrossfade
            if xfade > 0 {
                try await runXfadeChain(
                    ffmpeg: ffmpeg,
                    segmentURLs: segmentURLs,
                    durations: sortedRanges.map { $0.duration },
                    crossfade: xfade,
                    outputURL: croppedURL
                )
            } else {
                // concat demuxer needs a list file with absolute paths
                let listURL = URL(fileURLWithPath: "\(tempDir)/concat_list.txt")
                let listBody = segmentURLs.map { "file '\($0.path)'" }.joined(separator: "\n")
                try listBody.write(to: listURL, atomically: true, encoding: .utf8)

                let concatArgs: [String] = [
                    "-f", "concat", "-safe", "0",
                    "-i", listURL.path,
                    "-c", "copy",
                    "-movflags", "+faststart",
                    "-y", croppedURL.path
                ]
                let concatResult = try await ProcessRunner.run(ffmpeg, arguments: concatArgs)
                guard concatResult.succeeded else {
                    throw ExportError.exportFailed(concatResult.stderr)
                }
                try? FileManager.default.removeItem(at: listURL)
            }

            // Cleanup segment temp files
            for url in segmentURLs { try? FileManager.default.removeItem(at: url) }
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
            watermark: project.watermark,
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
        watermark: WatermarkSettings,
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

        // --- Pre-render watermark (static) ---
        let watermarkImage = SubtitleRenderer.renderWatermark(
            watermark, canvasSize: outputSize
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
            let needsOverlay = subtitleImage != nil || metadataImage != nil || watermarkImage != nil

            if needsOverlay {
                let newBuffer = drawOverlays(
                    onto: imageBuffer, width: width, height: height,
                    pool: pixelBufferAdaptor.pixelBufferPool,
                    metadataImage: metadataImage,
                    watermarkImage: watermarkImage,
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
        watermarkImage: CGImage?,
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

        // Draw watermark (under metadata + subtitle so they always read on top)
        if let watermarkImage {
            ctx.draw(watermarkImage, in: frameRect)
        }

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

    // MARK: - FFmpeg helpers (multi-range trim/crop)

    /// Build the crop/scale FFmpeg filter chain matching the project's crop mode.
    /// Identical math to the previous single-pass implementation, just factored out.
    private func buildCropFilterChain(
        crop: CropSettings,
        meta: VideoMetadata,
        outW: Int,
        outH: Int
    ) -> String {
        let sourceW = Double(meta.width)
        let sourceH = Double(meta.height)
        let targetW = Double(outW)
        let targetH = Double(outH)

        switch crop.mode {
        case .vertical:
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
            return "scale=\(evenScaledW):\(evenScaledH),crop=\(outW):\(outH):\(cropX):\(cropY)"

        case .horizontal:
            let blurLuma = Int(crop.blurRadius)
            let blurChroma = max(blurLuma / 4, 1)
            let zoom = crop.zoomScale
            let fitScale = min(targetW / sourceW, targetH / sourceH) * zoom
            var fgW = Int((sourceW * fitScale).rounded())
            var fgH = Int((sourceH * fitScale).rounded())
            fgW = min(fgW, outW)
            fgH = min(fgH, outH)
            fgW += fgW % 2
            fgH += fgH % 2
            let maxOffsetY = Int(targetH) - fgH
            let overlayY = Int(((crop.verticalOffset + 1.0) / 2.0) * Double(maxOffsetY))
            let overlayX = (outW - fgW) / 2
            return """
            split=2[bg][fg];\
            [bg]scale=\(outW):\(outH):force_original_aspect_ratio=increase,\
            crop=\(outW):\(outH),boxblur=\(blurLuma):\(blurChroma)[bgblur];\
            [fg]scale=\(fgW):\(fgH)[fgfit];\
            [bgblur][fgfit]overlay=\(overlayX):\(overlayY)
            """
        }
    }

    /// Chain xfade (video) + acrossfade (audio) across N pre-encoded segments.
    /// Each crossfade overlaps the previous segment's last `crossfade` seconds with the
    /// next segment's first `crossfade` seconds. Output duration is sum(durations) - (N-1)*crossfade.
    private func runXfadeChain(
        ffmpeg: String,
        segmentURLs: [URL],
        durations: [Double],
        crossfade: Double,
        outputURL: URL
    ) async throws {
        precondition(segmentURLs.count >= 2 && segmentURLs.count == durations.count)
        var args: [String] = []
        for url in segmentURLs {
            args += ["-i", url.path]
        }

        let durStr = String(format: "%.3f", crossfade)
        var filters: [String] = []
        var vLabel = "0:v"
        var aLabel = "0:a"
        var priorDuration = durations[0]  // duration of current chained output before next xfade
        let lastIndex = segmentURLs.count - 1
        for i in 1...lastIndex {
            let nextV = (i == lastIndex) ? "v" : "v\(i)"
            let nextA = (i == lastIndex) ? "a" : "a\(i)"
            let offset = priorDuration - crossfade
            let offsetStr = String(format: "%.3f", max(0, offset))
            filters.append("[\(vLabel)][\(i):v]xfade=transition=fade:duration=\(durStr):offset=\(offsetStr)[\(nextV)]")
            filters.append("[\(aLabel)][\(i):a]acrossfade=d=\(durStr)[\(nextA)]")
            vLabel = nextV
            aLabel = nextA
            priorDuration = priorDuration + durations[i] - crossfade
        }

        args += ["-filter_complex", filters.joined(separator: ";")]
        args += ["-map", "[v]", "-map", "[a]"]
        args += [
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k",
            "-r", "30",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            "-y", outputURL.path
        ]

        let result = try await ProcessRunner.run(ffmpeg, arguments: args)
        guard result.succeeded else {
            throw ExportError.exportFailed(result.stderr)
        }
    }

    /// Run FFmpeg to trim a single source range and crop/scale it to the output canvas.
    /// Each invocation produces a self-contained MP4 ready for concat-demuxer stitching.
    private func runTrimCrop(
        ffmpeg: String,
        inputURL: URL,
        range: TrimRange,
        filterChain: String,
        outputURL: URL
    ) async throws {
        var args: [String] = []
        args += ["-ss", String(format: "%.3f", range.startTime)]
        args += ["-i", inputURL.path]
        args += ["-t", String(format: "%.3f", range.duration)]
        args += [
            "-vf", filterChain,
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k",
            "-r", "30",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart",
            "-y", outputURL.path
        ]
        let result = try await ProcessRunner.run(ffmpeg, arguments: args)
        guard result.succeeded else {
            throw ExportError.exportFailed(result.stderr)
        }
    }
}
