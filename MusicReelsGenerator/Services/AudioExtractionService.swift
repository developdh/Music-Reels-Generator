import Foundation

enum AudioExtractionError: LocalizedError {
    case ffmpegNotFound
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Install with: brew install ffmpeg"
        case .extractionFailed(let msg):
            return "Audio extraction failed: \(msg)"
        }
    }
}

enum AudioExtractionService {
    /// Extract audio from video file as WAV (16kHz mono, ideal for whisper.cpp)
    static func extractAudio(
        from videoURL: URL,
        to outputURL: URL,
        onProgress: ((String) -> Void)? = nil
    ) async throws {
        guard let ffmpeg = ProcessRunner.findFFmpeg() else {
            throw AudioExtractionError.ffmpegNotFound
        }

        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)

        onProgress?("Extracting audio...")

        let args = [
            "-i", videoURL.path,
            "-vn",                  // no video
            "-acodec", "pcm_s16le", // 16-bit PCM
            "-ar", "16000",         // 16kHz sample rate (whisper.cpp expects this)
            "-ac", "1",             // mono
            "-y",                   // overwrite
            outputURL.path
        ]

        let result = try await ProcessRunner.run(ffmpeg, arguments: args)

        guard result.succeeded else {
            throw AudioExtractionError.extractionFailed(result.stderr)
        }

        onProgress?("Audio extraction complete.")
    }
}
