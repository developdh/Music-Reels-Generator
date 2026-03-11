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
        let outW = crop.outputWidth
        let outH = crop.outputHeight
        let meta = project.videoMetadata

        // --- Step 1: FFmpeg crop/scale → intermediate file ---
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
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "192k",
            "-r", "30",
            "-movflags", "+faststart",
            "-y", croppedURL.path
        ]

        onProgress(.exporting(progress: 0.05))
        print("FFmpeg crop: \(ffmpeg) \(ffmpegArgs.joined(separator: " "))")

        let cropResult = try await ProcessRunner.run(ffmpeg, arguments: ffmpegArgs)
        guard cropResult.succeeded else {
            throw ExportError.exportFailed(cropResult.stderr)
        }

        onProgress(.exporting(progress: 0.4))

        // --- Step 2: Burn subtitles frame-by-frame via AVAssetReader/Writer ---
        try? FileManager.default.removeItem(at: outputURL)

        try await burnSubtitlesFrameByFrame(
            inputURL: croppedURL,
            outputURL: outputURL,
            blocks: timedBlocks,
            style: project.subtitleStyle,
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

        // --- Pre-render subtitle images ---
        let subtitleImages = prerenderSubtitles(
            blocks: blocks, style: style, canvasSize: outputSize
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

            if let activeBlock, let subtitleImage = subtitleImages[activeBlock.id] {
                // Draw subtitle onto frame
                let newBuffer = drawSubtitle(
                    subtitleImage, onto: imageBuffer, width: width, height: height,
                    pool: pixelBufferAdaptor.pixelBufferPool
                )
                pixelBufferAdaptor.append(newBuffer ?? imageBuffer, withPresentationTime: presentationTime)
            } else {
                // Pass frame through unchanged
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

    // MARK: - Pre-render subtitles as CGImage

    /// Pre-render each block's subtitle as a transparent CGImage (avoids per-frame text layout)
    private func prerenderSubtitles(
        blocks: [LyricBlock],
        style: SubtitleStyle,
        canvasSize: CGSize
    ) -> [UUID: CGImage] {
        var result: [UUID: CGImage] = [:]
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)

        let jaFont = NSFont(name: style.japaneseFontFamily, size: style.japaneseFontSize)
            ?? NSFont.boldSystemFont(ofSize: style.japaneseFontSize)
        let koFont = NSFont(name: style.koreanFontFamily, size: style.koreanFontSize)
            ?? NSFont.systemFont(ofSize: style.koreanFontSize)
        let textColor = NSColor(Color(hex: style.textColorHex)).cgColor
        let outlineColor = NSColor(Color(hex: style.outlineColorHex)).cgColor

        for block in blocks {
            guard block.hasTimingData else { continue }

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { continue }

            // CG origin is bottom-left
            let jaAttrString = NSAttributedString(string: block.japanese, attributes: [
                .font: jaFont,
                .foregroundColor: NSColor(cgColor: textColor) ?? .white
            ])
            let koAttrString = NSAttributedString(string: block.korean, attributes: [
                .font: koFont,
                .foregroundColor: NSColor(cgColor: textColor) ?? .white
            ])

            let maxTextWidth = canvasSize.width - 60
            let jaSize = jaAttrString.boundingRect(
                with: CGSize(width: maxTextWidth, height: 500),
                options: [.usesLineFragmentOrigin]
            ).size
            let koSize = koAttrString.boundingRect(
                with: CGSize(width: maxTextWidth, height: 500),
                options: [.usesLineFragmentOrigin]
            ).size

            // Y positions (CG: origin bottom-left)
            let koY = style.bottomMargin
            let jaY = koY + koSize.height + style.lineSpacing

            // Draw with outline: draw text twice — stroke then fill
            ctx.saveGState()

            // Korean outline + fill
            let koX = (canvasSize.width - koSize.width) / 2
            drawOutlinedText(ctx: ctx, attrString: koAttrString,
                           at: CGPoint(x: koX, y: koY),
                           size: CGSize(width: maxTextWidth, height: koSize.height + 10),
                           outlineColor: outlineColor, outlineWidth: style.outlineWidth)

            // Japanese outline + fill
            let jaX = (canvasSize.width - jaSize.width) / 2
            drawOutlinedText(ctx: ctx, attrString: jaAttrString,
                           at: CGPoint(x: jaX, y: jaY),
                           size: CGSize(width: maxTextWidth, height: jaSize.height + 10),
                           outlineColor: outlineColor, outlineWidth: style.outlineWidth)

            ctx.restoreGState()

            if let image = ctx.makeImage() {
                result[block.id] = image
            }
        }

        return result
    }

    private func drawOutlinedText(
        ctx: CGContext,
        attrString: NSAttributedString,
        at point: CGPoint,
        size: CGSize,
        outlineColor: CGColor,
        outlineWidth: Double
    ) {
        let line = CTLineCreateWithAttributedString(attrString)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]

        // Draw outline
        ctx.saveGState()
        ctx.setTextDrawingMode(.stroke)
        ctx.setStrokeColor(outlineColor)
        ctx.setLineWidth(CGFloat(outlineWidth * 2))
        ctx.setLineJoin(.round)
        ctx.textPosition = point
        for run in runs {
            CTRunDraw(run, ctx, CFRange())
        }
        ctx.restoreGState()

        // Draw fill
        ctx.saveGState()
        ctx.setTextDrawingMode(.fill)
        ctx.textPosition = point
        for run in runs {
            CTRunDraw(run, ctx, CFRange())
        }
        ctx.restoreGState()
    }

    // MARK: - Composite subtitle image onto video frame

    private func drawSubtitle(
        _ subtitleImage: CGImage,
        onto pixelBuffer: CVPixelBuffer,
        width: Int, height: Int,
        pool: CVPixelBufferPool?
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

        // Draw subtitle overlay
        ctx.draw(subtitleImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(outputBuffer, [])

        return outputBuffer
    }

    func cancel() {}
}
