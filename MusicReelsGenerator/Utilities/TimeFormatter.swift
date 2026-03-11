import Foundation

enum TimeFormatter {
    static func format(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let centiseconds = Int((seconds - Double(totalSeconds)) * 100)
        return String(format: "%d:%02d.%02d", minutes, secs, centiseconds)
    }

    static func formatMMSS(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    static func assTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let centiseconds = Int((seconds - Double(Int(seconds))) * 100)
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, secs, centiseconds)
    }
}
