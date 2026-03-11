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

    private func prerenderSubtitles(
        blocks: [LyricBlock],
        style: SubtitleStyle,
        canvasSize: CGSize
    ) -> [UUID: CGImage] {
        var result: [UUID: CGImage] = [:]
        let width = Int(canvasSize.width)
        let height = Int(canvasSize.height)

        // Resolve fonts by family name using font descriptors.
        // NSFont(name:) expects a PostScript or full name, NOT a family name.
        // The style stores family names (e.g. "Hiragino Sans"), so we must use
        // NSFontDescriptor to resolve correctly.
        let fm = NSFontManager.shared
        var jaFont = resolveFont(family: style.japaneseFontFamily, size: style.japaneseFontSize)
        jaFont = fm.convert(jaFont, toHaveTrait: .boldFontMask)

        let koFont = resolveFont(family: style.koreanFontFamily, size: style.koreanFontSize)

        let textColor = NSColor(Color(hex: style.textColorHex))
        let outlineColor = NSColor(Color(hex: style.outlineColorHex))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let outlineR = max(style.outlineWidth, 1.0) // outline radius in pixels

        for block in blocks {
            guard block.hasTimingData else { continue }

            let image = NSImage(size: NSSize(width: width, height: height))
            image.lockFocus()

            guard NSGraphicsContext.current != nil else {
                image.unlockFocus()
                continue
            }

            let maxTextWidth = canvasSize.width - 60

            // Measure text sizes using fill attrs (no stroke — stroke changes metrics)
            let jaFillAttrs: [NSAttributedString.Key: Any] = [
                .font: jaFont,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]
            let koFillAttrs: [NSAttributedString.Key: Any] = [
                .font: koFont,
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle
            ]

            let jaStr = NSAttributedString(string: block.japanese, attributes: jaFillAttrs)
            let koStr = NSAttributedString(string: block.korean, attributes: koFillAttrs)

            let jaSize = jaStr.boundingRect(
                with: NSSize(width: maxTextWidth, height: 500),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
            let koSize = koStr.boundingRect(
                with: NSSize(width: maxTextWidth, height: 500),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size

            // Y positions (NSImage origin = bottom-left)
            let koY = style.bottomMargin
            let jaY = koY + koSize.height + style.lineSpacing

            let koRect = NSRect(
                x: (canvasSize.width - maxTextWidth) / 2,
                y: koY,
                width: maxTextWidth, height: koSize.height + 10
            )
            let jaRect = NSRect(
                x: (canvasSize.width - maxTextWidth) / 2,
                y: jaY,
                width: maxTextWidth, height: jaSize.height + 10
            )

            // --- Outline pass: draw text in outlineColor at offsets around origin ---
            let outlineJaAttrs: [NSAttributedString.Key: Any] = [
                .font: jaFont,
                .foregroundColor: outlineColor,
                .paragraphStyle: paragraphStyle
            ]
            let outlineKoAttrs: [NSAttributedString.Key: Any] = [
                .font: koFont,
                .foregroundColor: outlineColor,
                .paragraphStyle: paragraphStyle
            ]
            let outlineJaStr = NSAttributedString(string: block.japanese, attributes: outlineJaAttrs)
            let outlineKoStr = NSAttributedString(string: block.korean, attributes: outlineKoAttrs)

            let step: CGFloat = max(1.0, outlineR / 3.0)
            for dx in stride(from: -outlineR, through: outlineR, by: step) {
                for dy in stride(from: -outlineR, through: outlineR, by: step) {
                    if dx * dx + dy * dy > outlineR * outlineR { continue }
                    outlineJaStr.draw(in: jaRect.offsetBy(dx: dx, dy: dy))
                    outlineKoStr.draw(in: koRect.offsetBy(dx: dx, dy: dy))
                }
            }

            // --- Shadow pass ---
            if style.shadowEnabled {
                let shadowAttrs: [NSAttributedString.Key: Any] = [
                    .font: jaFont,
                    .foregroundColor: NSColor(white: 0, alpha: 0.25),
                    .paragraphStyle: paragraphStyle
                ]
                let shadowKoAttrs: [NSAttributedString.Key: Any] = [
                    .font: koFont,
                    .foregroundColor: NSColor(white: 0, alpha: 0.25),
                    .paragraphStyle: paragraphStyle
                ]
                let off: CGFloat = 2
                NSAttributedString(string: block.japanese, attributes: shadowAttrs)
                    .draw(in: jaRect.offsetBy(dx: off, dy: -off))
                NSAttributedString(string: block.korean, attributes: shadowKoAttrs)
                    .draw(in: koRect.offsetBy(dx: off, dy: -off))
            }

            // --- Fill pass: draw main text on top ---
            jaStr.draw(in: jaRect)
            koStr.draw(in: koRect)

            image.unlockFocus()

            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                result[block.id] = cgImage
            }
        }

        return result
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

    // MARK: - Font Resolution

    /// Resolve a font by family name using NSFontDescriptor.
    /// NSFont(name:) expects a PostScript/full name, not a family name.
    /// This method correctly resolves family names like "Hiragino Sans".
    private func resolveFont(family: String, size: Double) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family
        ])
        if let font = NSFont(descriptor: descriptor, size: size) {
            print("[Export Font] Resolved '\(family)' → \(font.fontName) (\(font.familyName ?? "?"))")
            return font
        }

        // Fallback: try NSFont(name:) in case family is actually a PostScript name
        if let font = NSFont(name: family, size: size) {
            print("[Export Font] Resolved '\(family)' via name → \(font.fontName)")
            return font
        }

        // Last resort: system font
        print("[Export Font] WARNING: Could not resolve '\(family)', falling back to system font")
        return NSFont.systemFont(ofSize: size)
    }

    func cancel() {}
}
