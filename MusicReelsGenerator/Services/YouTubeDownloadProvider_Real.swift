import Foundation

@objc(RealYouTubeDownloadProvider)
class RealYouTubeDownloadProvider: NSObject, YouTubeDownloadProvider {

    private static let scriptName = "yt_download.sh"

    var isEnabled: Bool {
        Self.findScript() != nil
    }

    func download(
        url: String,
        to directory: URL,
        onProgress: @escaping (YouTubeDownloadState) -> Void
    ) async throws -> URL {
        guard let scriptPath = Self.findScript() else {
            throw YouTubeDownloadError.scriptNotFound
        }

        onProgress(.validating)

        let result = try await ProcessRunner.runStreaming(
            "/bin/bash",
            arguments: [scriptPath, url, directory.path],
            timeout: 600
        ) { line in
            // Script outputs progress lines: PROGRESS:<percent>:<status text>
            if line.hasPrefix("PROGRESS:") {
                let parts = line.dropFirst("PROGRESS:".count).split(separator: ":", maxSplits: 1)
                if let pctStr = parts.first, let pct = Double(pctStr) {
                    let statusText = parts.count > 1 ? String(parts[1]) : ""
                    Task { @MainActor in
                        onProgress(.downloading(progress: pct / 100.0, statusText: statusText))
                    }
                }
            }
        }

        guard result.succeeded else {
            throw YouTubeDownloadError.downloadFailed(result.stderr)
        }

        // Find the downloaded file
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { ["mp4", "mkv", "webm", "mov"].contains($0.pathExtension.lowercased()) }

        guard let downloadedFile = files.first else {
            throw YouTubeDownloadError.downloadFailed("No output file found")
        }

        onProgress(.completed(downloadedFile))
        return downloadedFile
    }

    /// Search for external script in Application Support
    private static func findScript() -> String? {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let scriptPath = appSupport
            .appendingPathComponent("MusicReelsGenerator/Scripts/\(scriptName)")
            .path

        guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
            return nil
        }
        return scriptPath
    }
}
