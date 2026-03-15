import Foundation

struct IgnoreRegion: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: Double
    var endTime: Double
    var label: String

    init(id: UUID = UUID(), startTime: Double, endTime: Double, label: String = "") {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.label = label
    }

    var duration: Double {
        max(0, endTime - startTime)
    }

    func contains(time: Double) -> Bool {
        time >= startTime && time <= endTime
    }

    func overlaps(segmentStart: Double, segmentEnd: Double) -> Bool {
        segmentStart < endTime && segmentEnd > startTime
    }

    mutating func clamp(to sourceDuration: Double) {
        startTime = max(0, min(startTime, sourceDuration))
        endTime = max(startTime + 0.1, min(endTime, sourceDuration))
    }
}
