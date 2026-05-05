import Foundation

/// Anchor corner for the watermark overlay. The image's edge nearest to the
/// chosen corner is positioned by `xMargin` / `yMargin` pixels in canvas space.
enum WatermarkPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"

    var id: String { rawValue }
}

/// User-supplied logo / watermark image overlaid on the rendered video.
/// The image bytes are embedded as PNG data so projects stay self-contained
/// and survive file relocations on the user's side.
struct WatermarkSettings: Codable, Equatable {
    var enabled: Bool = false
    /// PNG-encoded bytes. Nil when the user hasn't picked an image yet.
    var imageData: Data?
    var position: WatermarkPosition = .bottomRight
    /// Image width as a percentage of the output canvas width (5–50).
    var widthPercent: Double = 15.0
    /// Pixel offset from the chosen corner along the X axis (0–400).
    var xMargin: Double = 40.0
    /// Pixel offset from the chosen corner along the Y axis (0–400).
    var yMargin: Double = 40.0
    /// Final draw alpha (0.0–1.0). 1.0 = fully opaque.
    var opacity: Double = 1.0

    /// Whether the renderer should produce an output image.
    var shouldRender: Bool {
        enabled && imageData != nil
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, imageData, position, widthPercent, xMargin, yMargin, opacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
        position = try c.decodeIfPresent(WatermarkPosition.self, forKey: .position) ?? .bottomRight
        widthPercent = try c.decodeIfPresent(Double.self, forKey: .widthPercent) ?? 15.0
        xMargin = try c.decodeIfPresent(Double.self, forKey: .xMargin) ?? 40.0
        yMargin = try c.decodeIfPresent(Double.self, forKey: .yMargin) ?? 40.0
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
    }
}
