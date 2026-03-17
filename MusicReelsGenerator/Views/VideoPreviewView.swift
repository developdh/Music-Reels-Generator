import SwiftUI
import AVKit
import AppKit

/// Renders AVPlayerLayer directly — gives us control over gravity and frame
struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    class PlayerHostView: NSView {
        var player: AVPlayer? {
            didSet { playerLayer.player = player }
        }

        private let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.addSublayer(playerLayer)
            playerLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

struct VideoPreviewView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        ZStack {
            if let player = vm.player {
                // True vertical crop preview
                CroppedVideoPreview(
                    player: player,
                    videoMetadata: vm.project.videoMetadata,
                    cropSettings: vm.project.cropSettings,
                    subtitleStyle: vm.project.subtitleStyle,
                    metadataOverlay: vm.project.metadataOverlay,
                    currentBlock: vm.currentBlock
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Import a video to get started")
                        .foregroundColor(.secondary)
                    Text("File > Import Video or click 'Import Video' above")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.05))
            }
        }
    }
}

/// Shows the video scaled-to-fill into a 9:16 container with crop offset applied
struct CroppedVideoPreview: View {
    let player: AVPlayer
    let videoMetadata: VideoMetadata
    let cropSettings: CropSettings
    let subtitleStyle: SubtitleStyle
    let metadataOverlay: MetadataOverlaySettings
    let currentBlock: LyricBlock?

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            // Fit a 9:16 rectangle into the available container
            let targetAspect: CGFloat = 9.0 / 16.0
            let previewSize = fitSize(aspect: targetAspect, into: containerSize)

            ZStack {
                Color.black

                // 9:16 preview frame
                ZStack {
                    if cropSettings.mode == .horizontal {
                        horizontalModeVideo(previewSize: previewSize)
                    } else {
                        croppedVideo(previewSize: previewSize)
                            .frame(width: previewSize.width, height: previewSize.height)
                            .clipped()
                    }

                    let canvasSize = CGSize(
                        width: CGFloat(cropSettings.outputWidth),
                        height: CGFloat(cropSettings.outputHeight)
                    )

                    // Metadata overlay (top-left title/artist)
                    MetadataOverlayPreview(
                        settings: metadataOverlay,
                        previewSize: previewSize,
                        canvasSize: canvasSize
                    )

                    // Subtitle overlay — rendered at export canvas size, scaled to preview
                    if let block = currentBlock {
                        SubtitleOverlayView(
                            block: block,
                            style: subtitleStyle,
                            previewSize: previewSize,
                            canvasSize: canvasSize
                        )
                    }
                }
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(Rectangle())
            }
        }
    }

    /// 가로모드: blurred background + fitted foreground
    @ViewBuilder
    private func horizontalModeVideo(previewSize: CGSize) -> some View {
        let srcW = CGFloat(max(videoMetadata.width, 1))
        let srcH = CGFloat(max(videoMetadata.height, 1))
        let targetW = previewSize.width
        let targetH = previewSize.height

        // Background: scale to fill (cover) + blur
        let bgScale = max(targetW / srcW, targetH / srcH)
        let bgW = srcW * bgScale
        let bgH = srcH * bgScale

        // Foreground: scale to fit + zoom
        let zoom = CGFloat(cropSettings.zoomScale)
        let fgScale = min(targetW / srcW, targetH / srcH) * zoom
        let fgW = min(srcW * fgScale, targetW)
        let fgH = min(srcH * fgScale, targetH)

        // Vertical offset for foreground
        let maxOffsetY = targetH - fgH
        let fgY = ((CGFloat(cropSettings.verticalOffset) + 1.0) / 2.0) * maxOffsetY - maxOffsetY / 2.0

        ZStack {
            // Blurred background layer
            PlayerLayerView(player: player)
                .frame(width: bgW, height: bgH)
                .clipped()
                .blur(radius: CGFloat(cropSettings.blurRadius))
                .frame(width: targetW, height: targetH)
                .clipped()

            // Fitted foreground layer
            PlayerLayerView(player: player)
                .frame(width: fgW, height: fgH)
                .clipped()
                .offset(y: fgY)
        }
        .frame(width: targetW, height: targetH)
        .clipped()
    }

    /// The video layer, scaled to fill the 9:16 preview and offset by crop sliders
    @ViewBuilder
    private func croppedVideo(previewSize: CGSize) -> some View {
        let srcW = CGFloat(max(videoMetadata.width, 1))
        let srcH = CGFloat(max(videoMetadata.height, 1))
        let targetW = previewSize.width
        let targetH = previewSize.height

        // Scale to fill (cover): use the larger scale factor, then apply zoom
        let scaleX = targetW / srcW
        let scaleY = targetH / srcH
        let zoom = CGFloat(cropSettings.zoomScale)
        let scale = max(scaleX, scaleY) * zoom

        let scaledW = srcW * scale
        let scaledH = srcH * scale

        // Overflow that can be panned
        let overflowX = scaledW - targetW
        let overflowY = scaledH - targetH

        // Convert -1..1 offset to pixel shift (-overflow/2 .. +overflow/2)
        let offsetX = -CGFloat(cropSettings.horizontalOffset) * overflowX / 2.0
        let offsetY = -CGFloat(cropSettings.verticalOffset) * overflowY / 2.0

        PlayerLayerView(player: player)
            .frame(width: scaledW, height: scaledH)
            .offset(x: offsetX, y: offsetY)
    }

    private func fitSize(aspect: CGFloat, into container: CGSize) -> CGSize {
        let byWidth = CGSize(width: container.width, height: container.width / aspect)
        let byHeight = CGSize(width: container.height * aspect, height: container.height)

        if byWidth.height <= container.height {
            return byWidth
        }
        return byHeight
    }
}

/// Preview metadata overlay (top-left title/artist) using the same renderer as export.
struct MetadataOverlayPreview: View {
    let settings: MetadataOverlaySettings
    let previewSize: CGSize
    let canvasSize: CGSize

    var body: some View {
        if let cgImage = SubtitleRenderer.renderMetadataOverlay(settings, canvasSize: canvasSize) {
            Image(nsImage: NSImage(cgImage: cgImage, size: canvasSize))
                .resizable()
                .interpolation(.high)
                .frame(width: previewSize.width, height: previewSize.height)
                .allowsHitTesting(false)
        }
    }
}

/// Preview subtitle overlay that uses the exact same Core Graphics renderer as export.
/// Renders at canonical export canvas size, then scales down to preview size.
struct SubtitleOverlayView: View {
    let block: LyricBlock
    let style: SubtitleStyle
    let previewSize: CGSize
    let canvasSize: CGSize

    var body: some View {
        if let cgImage = SubtitleRenderer.renderBlock(
            block, style: style, canvasSize: canvasSize
        ) {
            Image(nsImage: NSImage(cgImage: cgImage, size: canvasSize))
                .resizable()
                .interpolation(.high)
                .frame(width: previewSize.width, height: previewSize.height)
                .allowsHitTesting(false)
        }
    }
}
