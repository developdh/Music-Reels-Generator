import SwiftUI
import AVKit
import AppKit

/// NSViewRepresentable wrapper for AVPlayerView (avoids SwiftUI VideoPlayer crash outside .app bundle)
struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

struct VideoPreviewView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        ZStack {
            if let player = vm.player {
                GeometryReader { geo in
                    ZStack {
                        NativeVideoPlayerView(player: player)

                        // Crop preview overlay
                        if vm.project.videoMetadata.isLandscape {
                            CropOverlayView(
                                videoSize: CGSize(
                                    width: CGFloat(vm.project.videoMetadata.width),
                                    height: CGFloat(vm.project.videoMetadata.height)
                                ),
                                cropSettings: vm.project.cropSettings,
                                containerSize: geo.size
                            )
                        }

                        // Subtitle overlay
                        if let block = vm.currentBlock {
                            SubtitleOverlayView(
                                block: block,
                                style: vm.project.subtitleStyle
                            )
                        }
                    }
                }
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

struct CropOverlayView: View {
    let videoSize: CGSize
    let cropSettings: CropSettings
    let containerSize: CGSize

    var body: some View {
        GeometryReader { _ in
            let targetRatio = CGFloat(cropSettings.outputWidth) / CGFloat(cropSettings.outputHeight)
            let displayScale = min(containerSize.width / videoSize.width, containerSize.height / videoSize.height)
            let displayW = videoSize.width * displayScale
            let displayH = videoSize.height * displayScale

            let cropDisplayH = displayH
            let cropDisplayW = cropDisplayH * targetRatio
            let maxOffset = (displayW - cropDisplayW) / 2.0
            let offsetX = CGFloat(cropSettings.horizontalOffset) * maxOffset

            let cropX = (containerSize.width - cropDisplayW) / 2.0 + offsetX
            let cropY = (containerSize.height - cropDisplayH) / 2.0

            ZStack {
                Color.black.opacity(0.4)
                    .mask(
                        Rectangle()
                            .overlay(
                                Rectangle()
                                    .frame(width: cropDisplayW, height: cropDisplayH)
                                    .position(x: cropX + cropDisplayW / 2, y: cropY + cropDisplayH / 2)
                                    .blendMode(.destinationOut)
                            )
                            .compositingGroup()
                    )

                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: cropDisplayW, height: cropDisplayH)
                    .position(x: cropX + cropDisplayW / 2, y: cropY + cropDisplayH / 2)
            }
            .allowsHitTesting(false)
        }
    }
}

struct SubtitleOverlayView: View {
    let block: LyricBlock
    let style: SubtitleStyle

    var body: some View {
        VStack(spacing: style.lineSpacing) {
            Text(block.japanese)
                .font(.system(size: style.japaneseFontSize, weight: .bold))
                .foregroundColor(style.textColor)
                .shadow(color: style.outlineColor.opacity(0.8), radius: style.outlineWidth)
                .shadow(color: style.outlineColor.opacity(0.6), radius: style.outlineWidth * 0.5)

            Text(block.korean)
                .font(.system(size: style.koreanFontSize))
                .foregroundColor(style.textColor)
                .shadow(color: style.outlineColor.opacity(0.8), radius: style.outlineWidth)
                .shadow(color: style.outlineColor.opacity(0.6), radius: style.outlineWidth * 0.5)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, style.bottomMargin / 10)
    }
}
