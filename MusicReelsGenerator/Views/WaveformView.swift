import SwiftUI

/// Draws a centered, mirrored waveform from a normalized peak array.
struct WaveformView: View {
    let peaks: [Float]
    var playFrac: Double = 0
    var startFrac: Double = 0
    var endFrac: Double = 1
    var baseColor: Color = Color.secondary.opacity(0.55)
    var playedColor: Color = .accentColor
    var dimmedColor: Color = Color.secondary.opacity(0.2)

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }

            let count = peaks.count
            let mid = size.height / 2
            let barWidth = max(0.5, size.width / CGFloat(count))
            let lineWidth = max(0.7, barWidth - 0.5)
            let halfH = size.height / 2 - 1

            let safeStart = max(0, min(startFrac, 1))
            let safeEnd = max(safeStart, min(endFrac, 1))
            let safePlay = max(0, min(playFrac, 1))

            for i in 0..<count {
                let p = CGFloat(max(0.02, peaks[i]))
                let h = max(1.5, p * halfH)
                let frac = (Double(i) + 0.5) / Double(count)
                let x = CGFloat(frac) * size.width

                let inRange = frac >= safeStart && frac <= safeEnd
                let played = inRange && frac <= safePlay

                let color: Color
                if !inRange {
                    color = dimmedColor
                } else if played {
                    color = playedColor
                } else {
                    color = baseColor
                }

                var path = Path()
                path.move(to: CGPoint(x: x, y: mid - h))
                path.addLine(to: CGPoint(x: x, y: mid + h))
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
            }
        }
    }
}

/// A custom playback scrubber with a waveform background, trim region overlay,
/// and a draggable playhead. Replaces the system Slider in the playback bar.
struct WaveformScrubberView: View {
    let peaks: [Float]
    let duration: Double
    let currentTime: Double
    let trimStart: Double
    let trimEnd: Double
    let isTrimActive: Bool
    let isEnabled: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let dur = max(duration, 0.01)
            let playFrac = min(max(currentTime / dur, 0), 1)
            let startFrac = isTrimActive ? min(max(trimStart / dur, 0), 1) : 0
            let endFrac = isTrimActive ? min(max(trimEnd / dur, 0), 1) : 1

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))

                if peaks.isEmpty {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 2)
                        .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    WaveformView(
                        peaks: peaks,
                        playFrac: playFrac,
                        startFrac: startFrac,
                        endFrac: endFrac
                    )
                    .padding(.vertical, 3)
                }

                if isTrimActive {
                    Rectangle()
                        .fill(Color.black.opacity(0.32))
                        .frame(width: max(0, w * startFrac))
                    Rectangle()
                        .fill(Color.black.opacity(0.32))
                        .frame(width: max(0, w * (1 - endFrac)))
                        .offset(x: w * endFrac)
                }

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5, height: h)
                    .offset(x: w * playFrac - 0.75)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, w > 0 else { return }
                        let frac = max(0, min(value.location.x / w, 1))
                        onSeek(frac * dur)
                    }
            )
            .opacity(isEnabled ? 1 : 0.5)
        }
    }
}
