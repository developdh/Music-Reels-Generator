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
                    croppedVideo(previewSize: previewSize)
                        .frame(width: previewSize.width, height: previewSize.height)
                        .clipped()

                    // Subtitle overlay — positioned relative to the 9:16 frame
                    if let block = currentBlock {
                        SubtitleOverlayView(
                            block: block,
                            style: subtitleStyle,
                            previewHeight: previewSize.height,
                            outputHeight: CGFloat(cropSettings.outputHeight)
                        )
                    }
                }
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(Rectangle())
            }
        }
    }

    /// The video layer, scaled to fill the 9:16 preview and offset by crop sliders
    @ViewBuilder
    private func croppedVideo(previewSize: CGSize) -> some View {
        let srcW = CGFloat(max(videoMetadata.width, 1))
        let srcH = CGFloat(max(videoMetadata.height, 1))
        let targetW = previewSize.width
        let targetH = previewSize.height

        // Scale to fill (cover): use the larger scale factor
        let scaleX = targetW / srcW
        let scaleY = targetH / srcH
        let scale = max(scaleX, scaleY)

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

struct SubtitleOverlayView: View {
    let block: LyricBlock
    let style: SubtitleStyle
    let previewHeight: CGFloat
    let outputHeight: CGFloat

    /// Scale factor from output pixels to preview pixels
    private var previewScale: CGFloat {
        previewHeight / outputHeight
    }

    var body: some View {
        VStack(spacing: style.lineSpacing * previewScale) {
            Text(block.japanese)
                .font(.custom(style.japaneseFontFamily, size: style.japaneseFontSize * previewScale))
                .fontWeight(.bold)
                .foregroundColor(style.textColor)
                .shadow(color: style.outlineColor.opacity(0.9), radius: style.outlineWidth * previewScale)
                .shadow(color: style.outlineColor.opacity(0.7), radius: style.outlineWidth * previewScale * 0.5)

            Text(block.korean)
                .font(.custom(style.koreanFontFamily, size: style.koreanFontSize * previewScale))
                .foregroundColor(style.textColor)
                .shadow(color: style.outlineColor.opacity(0.9), radius: style.outlineWidth * previewScale)
                .shadow(color: style.outlineColor.opacity(0.7), radius: style.outlineWidth * previewScale * 0.5)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20 * previewScale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, style.bottomMargin * previewScale)
    }
}
