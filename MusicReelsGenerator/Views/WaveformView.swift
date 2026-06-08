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

/// A zoomed waveform around the selected lyric block with draggable start/end
/// handles, for precise manual timing against the audio. Reuses the global peak
/// array (sliced to a context window around the block). Dragging a handle commits
/// via the supplied callbacks (which route through `updateBlock`, so edits coalesce
/// into one undo step and mark the block manually-adjusted); tapping elsewhere seeks.
struct BlockTimingWaveformView: View {
    let peaks: [Float]
    let duration: Double
    let blockStart: Double
    let blockEnd: Double
    let currentTime: Double
    let onSetStart: (Double) -> Void
    let onSetEnd: (Double) -> Void
    let onSeek: (Double) -> Void

    private enum DragMode { case start, end, seek }
    @State private var dragMode: DragMode? = nil

    private let minDur = 0.05
    private let grabRadius: CGFloat = 16

    /// Context window around the block: padded, with a minimum visible width,
    /// clamped to the track.
    private var window: (start: Double, end: Double) {
        let dur = max(duration, 0.01)
        let pad = max(1.0, (blockEnd - blockStart) * 0.5)
        var s = blockStart - pad
        var e = blockEnd + pad
        let minWidth = 4.0
        if e - s < minWidth {
            let mid = (s + e) / 2
            s = mid - minWidth / 2
            e = mid + minWidth / 2
        }
        s = max(0, s)
        e = min(dur, max(e, s + 0.01))
        return (s, e)
    }

    private var slice: [Float] {
        guard !peaks.isEmpty, duration > 0 else { return [] }
        let win = window
        let n = peaks.count
        let i0 = max(0, min(n - 1, Int(win.start / duration * Double(n))))
        let i1 = max(i0 + 1, min(n, Int(win.end / duration * Double(n))))
        return Array(peaks[i0..<i1])
    }

    private func frac(_ t: Double) -> Double {
        let win = window
        let wd = win.end - win.start
        guard wd > 0 else { return 0 }
        return min(max((t - win.start) / wd, 0), 1)
    }

    private func time(atX x: CGFloat, width w: CGFloat) -> Double {
        let win = window
        guard w > 0 else { return win.start }
        let f = min(max(Double(x / w), 0), 1)
        return win.start + f * (win.end - win.start)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sFrac = frac(blockStart)
            let eFrac = frac(blockEnd)
            let pFrac = frac(currentTime)
            let win = window

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))

                if slice.isEmpty {
                    Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 2)
                } else {
                    WaveformView(peaks: slice, playFrac: pFrac, startFrac: sFrac, endFrac: eFrac)
                        .padding(.vertical, 3)
                }

                // Playhead (only when inside the window)
                if currentTime >= win.start && currentTime <= win.end {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 1.5, height: h)
                        .offset(x: w * pFrac - 0.75)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .allowsHitTesting(false)
                }

                // Start handle (green) and end handle (red)
                handle(color: .green, x: w * sFrac, h: h, alignTop: true)
                handle(color: .red, x: w * eFrac, h: h, alignTop: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard w > 0 else { return }
                        let mode: DragMode
                        if let m = dragMode {
                            mode = m
                        } else {
                            let x = v.location.x
                            let sx = w * frac(blockStart)
                            let ex = w * frac(blockEnd)
                            if abs(x - sx) <= grabRadius && abs(x - sx) <= abs(x - ex) {
                                mode = .start
                            } else if abs(x - ex) <= grabRadius {
                                mode = .end
                            } else {
                                mode = .seek
                            }
                            dragMode = mode
                        }
                        let t = time(atX: v.location.x, width: w)
                        switch mode {
                        case .start: onSetStart(min(max(t, win.start), blockEnd - minDur))
                        case .end:   onSetEnd(max(min(t, win.end), blockStart + minDur))
                        case .seek:  onSeek(t)
                        }
                    }
                    .onEnded { _ in dragMode = nil }
            )
        }
    }

    /// A draggable boundary marker: a colored vertical line with a small cap.
    private func handle(color: Color, x: CGFloat, h: CGFloat, alignTop: Bool) -> some View {
        ZStack(alignment: alignTop ? .top : .bottom) {
            Rectangle()
                .fill(color)
                .frame(width: 2, height: h)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 7, height: h)
        .offset(x: x - 3.5)
        .shadow(color: .black.opacity(0.4), radius: 1)
        .allowsHitTesting(false)   // dragging handled by the container gesture
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
