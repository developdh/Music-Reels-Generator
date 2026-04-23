import Foundation

enum SubtitleExportError: LocalizedError {
    case noTimedBlocks
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTimedBlocks:
            return "No lyrics with timing data. Run alignment or set times manually."
        case .writeFailed(let msg):
            return "Failed to write subtitle file: \(msg)"
        }
    }
}

/// Generates LRC / SRT subtitle files from timed lyric blocks.
/// Uses source-absolute timing (pairs with the original source video/audio, not the trimmed export).
enum SubtitleExportService {

    // MARK: - SRT

    static func exportSRT(project: Project, to url: URL) throws {
        let timed = project.lyricBlocks
            .filter { $0.hasTimingData }
            .sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
        guard !timed.isEmpty else { throw SubtitleExportError.noTimedBlocks }

        var out = ""
        for (i, block) in timed.enumerated() {
            guard let start = block.startTime, let end = block.endTime else { continue }
            out += "\(i + 1)\n"
            out += "\(srtTimestamp(start)) --> \(srtTimestamp(end))\n"
            out += block.japanese
            if !block.korean.isEmpty {
                out += "\n" + block.korean
            }
            out += "\n\n"
        }

        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw SubtitleExportError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - LRC

    static func exportLRC(project: Project, to url: URL) throws {
        let timed = project.lyricBlocks
            .filter { $0.hasTimingData }
            .sorted { ($0.startTime ?? 0) < ($1.startTime ?? 0) }
        guard !timed.isEmpty else { throw SubtitleExportError.noTimedBlocks }

        var out = ""
        let title = project.metadataOverlay.titleText.trimmingCharacters(in: .whitespaces)
        let artist = project.metadataOverlay.artistText.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { out += "[ti:\(title)]\n" }
        if !artist.isEmpty { out += "[ar:\(artist)]\n" }
        out += "[tool:Music Reels Generator]\n"

        for block in timed {
            guard let start = block.startTime else { continue }
            let stamp = lrcTimestamp(start)
            out += "\(stamp)\(sanitizeLRCLine(block.japanese))\n"
            // Bilingual LRC: repeat same timestamp for secondary line so players can display
            // it as a translation line (supported by Musixmatch, SyncLyrics, etc.)
            if !block.korean.isEmpty {
                out += "\(stamp)\(sanitizeLRCLine(block.korean))\n"
            }
        }

        do {
            try out.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw SubtitleExportError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Timestamp helpers

    /// `HH:MM:SS,mmm` (SRT uses comma as decimal separator)
    private static func srtTimestamp(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalMs = Int((clamped * 1000).rounded())
        let h = totalMs / 3_600_000
        let m = (totalMs % 3_600_000) / 60_000
        let s = (totalMs % 60_000) / 1000
        let ms = totalMs % 1000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    /// `[MM:SS.cc]` (LRC uses centiseconds, minutes can exceed 59)
    private static func lrcTimestamp(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let totalCs = Int((clamped * 100).rounded())
        let m = totalCs / 6000
        let s = (totalCs % 6000) / 100
        let cs = totalCs % 100
        return String(format: "[%02d:%02d.%02d]", m, s, cs)
    }

    /// Strip `[` `]` from lyric text to avoid confusing LRC parsers that treat them as tags.
    private static func sanitizeLRCLine(_ text: String) -> String {
        text.replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
    }
}
