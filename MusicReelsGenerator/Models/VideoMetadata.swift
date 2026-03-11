import Foundation

struct VideoMetadata: Codable, Equatable {
    var duration: Double = 0
    var width: Int = 0
    var height: Int = 0
    var frameRate: Double = 30
    var fileSize: Int64 = 0

    var aspectRatioString: String {
        guard height > 0 else { return "—" }
        let ratio = Double(width) / Double(height)
        if abs(ratio - 16.0/9.0) < 0.1 { return "16:9" }
        if abs(ratio - 9.0/16.0) < 0.1 { return "9:16" }
        if abs(ratio - 4.0/3.0) < 0.1 { return "4:3" }
        return String(format: "%.2f:1", ratio)
    }

    var isLandscape: Bool {
        width > height
    }
}
