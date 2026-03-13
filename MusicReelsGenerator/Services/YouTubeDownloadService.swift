import Foundation

// MARK: - State & Errors

enum YouTubeDownloadState: Equatable {
    case idle
    case validating
    case downloading(progress: Double, statusText: String)
    case completed(URL)
    case failed(String)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.validating, .validating): return true
        case (.downloading(let lp, _), .downloading(let rp, _)): return lp == rp
        case (.completed(let lu), .completed(let ru)): return lu == ru
        case (.failed(let lm), .failed(let rm)): return lm == rm
        default: return false
        }
    }
}

enum YouTubeDownloadError: LocalizedError {
    case featureDisabled
    case ytdlpNotFound
    case invalidURL
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .featureDisabled:
            return "이 기능은 현재 비활성화 상태입니다."
        case .ytdlpNotFound:
            return "yt-dlp not found. Install with: brew install yt-dlp"
        case .invalidURL:
            return "Invalid URL"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        }
    }
}

// MARK: - Protocol

protocol YouTubeDownloadProvider {
    var isEnabled: Bool { get }
    func download(
        url: String,
        to directory: URL,
        onProgress: @escaping (YouTubeDownloadState) -> Void
    ) async throws -> URL
}

// MARK: - Stub (public builds)

struct StubYouTubeDownloadProvider: YouTubeDownloadProvider {
    var isEnabled: Bool { false }

    func download(
        url: String,
        to directory: URL,
        onProgress: @escaping (YouTubeDownloadState) -> Void
    ) async throws -> URL {
        throw YouTubeDownloadError.featureDisabled
    }
}

// MARK: - Registry (runtime feature toggle via NSClassFromString)

enum YouTubeDownloadRegistry {
    private static let _resolved: YouTubeDownloadProvider = {
        if let cls = NSClassFromString("RealYouTubeDownloadProvider") as? (YouTubeDownloadProvider & NSObject).Type {
            return cls.init()
        }
        return StubYouTubeDownloadProvider()
    }()

    static var provider: YouTubeDownloadProvider { _resolved }
}
