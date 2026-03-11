import Foundation

enum CropMode: String, Codable, CaseIterable {
    case centerCrop = "center"
    case manualOffset = "manual"
}

struct CropSettings: Codable, Equatable {
    var mode: CropMode = .centerCrop
    var horizontalOffset: Double = 0.0 // -1.0 (left) to 1.0 (right), 0 = center
    var verticalOffset: Double = 0.0   // -1.0 (top) to 1.0 (bottom), 0 = center
    var outputWidth: Int = 1080
    var outputHeight: Int = 1920

    var aspectRatio: Double {
        Double(outputWidth) / Double(outputHeight)
    }
}
