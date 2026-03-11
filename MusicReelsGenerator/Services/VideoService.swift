import Foundation
import AVFoundation

enum VideoServiceError: LocalizedError {
    case invalidURL
    case metadataExtractionFailed
    case trackNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid video file URL."
        case .metadataExtractionFailed: return "Could not read video metadata."
        case .trackNotFound: return "No video track found in file."
        }
    }
}

enum VideoService {
    static func extractMetadata(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = tracks.first else {
            throw VideoServiceError.trackNotFound
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)

        // Apply transform to get actual dimensions (handles rotated videos)
        let transformedSize = naturalSize.applying(transform)
        let width = Int(abs(transformedSize.width))
        let height = Int(abs(transformedSize.height))

        let fileSize: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        } else {
            fileSize = 0
        }

        return VideoMetadata(
            duration: CMTimeGetSeconds(duration),
            width: width,
            height: height,
            frameRate: Double(nominalFrameRate),
            fileSize: fileSize
        )
    }
}
