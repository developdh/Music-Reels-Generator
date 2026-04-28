import Foundation
import AVFoundation

enum WaveformError: LocalizedError {
    case noAudioTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in video."
        case .readerFailed(let msg):
            return "Waveform extraction failed: \(msg)"
        }
    }
}

/// Reads audio from a video file via AVAssetReader and produces a normalized
/// peak-amplitude array suitable for waveform visualization. Runs entirely off
/// the main actor.
enum WaveformService {
    static func extractPeaks(
        from videoURL: URL,
        bucketCount: Int = 2000
    ) async throws -> [Float] {
        let asset = AVURLAsset(url: videoURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw WaveformError.noAudioTrack }

        let duration = try await asset.load(.duration)
        let durSec = CMTimeGetSeconds(duration)
        guard durSec.isFinite, durSec > 0, bucketCount > 0 else { return [] }

        let sampleRate: Double = 8000
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw WaveformError.readerFailed("cannot add audio output")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw WaveformError.readerFailed(reader.error?.localizedDescription ?? "startReading failed")
        }

        let totalSamples = max(1, Int(durSec * sampleRate))
        let samplesPerBucket = max(1, totalSamples / bucketCount)

        var peaks = [Float](repeating: 0, count: bucketCount)
        var bucketIdx = 0
        var bucketRemaining = samplesPerBucket
        var currentMax: Int32 = 0

        while reader.status == .reading, let buffer = output.copyNextSampleBuffer() {
            autoreleasepool {
                guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { return }
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: nil,
                    totalLengthOut: &totalLength,
                    dataPointerOut: &dataPointer
                )
                guard status == kCMBlockBufferNoErr, let p = dataPointer else { return }

                let sampleCount = totalLength / MemoryLayout<Int16>.size
                let samples = UnsafeRawPointer(p).assumingMemoryBound(to: Int16.self)

                var i = 0
                while i < sampleCount {
                    let take = min(bucketRemaining, sampleCount - i)
                    var localMax = currentMax
                    var j = 0
                    while j < take {
                        let v = Int32(samples[i + j])
                        let amp = v < 0 ? -v : v
                        if amp > localMax { localMax = amp }
                        j += 1
                    }
                    currentMax = localMax
                    i += take
                    bucketRemaining -= take

                    if bucketRemaining == 0 {
                        if bucketIdx < bucketCount {
                            peaks[bucketIdx] = Float(currentMax) / Float(Int16.max)
                        }
                        bucketIdx += 1
                        currentMax = 0
                        bucketRemaining = samplesPerBucket
                    }
                }
            }
        }

        if reader.status == .failed {
            throw WaveformError.readerFailed(reader.error?.localizedDescription ?? "reader failed")
        }

        if bucketIdx < bucketCount, currentMax > 0 {
            peaks[bucketIdx] = Float(currentMax) / Float(Int16.max)
        }

        let globalMax = peaks.max() ?? 0
        if globalMax > 0 {
            let scale = 1 / globalMax
            for k in peaks.indices {
                peaks[k] *= scale
            }
        }

        return peaks
    }
}
