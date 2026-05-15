import SwiftUI
import AppKit

struct TrimInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    private var crossfadeLabelText: String {
        let d = vm.project.trimSettings.crossfadeDuration
        if d <= 0 { return L10n.Trim.crossfadeOff(vm.lang) }
        return L10n.Trim.crossfadeLabel(vm.lang, seconds: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Trim.settings(vm.lang))
                    .font(.headline)
                Spacer()
                if vm.project.hasVideo {
                    Button {
                        vm.addTrimRange()
                    } label: {
                        Label(L10n.Trim.addRange(vm.lang), systemImage: "plus")
                    }
                    .controlSize(.small)
                }
            }

            if !vm.project.hasVideo {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(L10n.Trim.importVideoFirst(vm.lang))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(Array(vm.project.trimSettings.sortedRanges.enumerated()), id: \.element.id) { index, range in
                    TrimRangeBox(index: index + 1, range: range)
                }

                // Crossfade between ranges (only relevant with 2+ ranges)
                if vm.project.trimSettings.ranges.count >= 2 {
                    GroupBox(L10n.Trim.crossfade(vm.lang)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(crossfadeLabelText)
                                    .font(.caption)
                                    .monospacedDigit()
                                Spacer()
                                if vm.project.trimSettings.crossfadeDuration > 0 {
                                    Button(L10n.Trim.crossfadeOff(vm.lang)) {
                                        vm.setCrossfadeDuration(0)
                                    }
                                    .controlSize(.mini)
                                }
                            }
                            Slider(
                                value: Binding(
                                    get: { vm.project.trimSettings.crossfadeDuration },
                                    set: { vm.setCrossfadeDuration($0) }
                                ),
                                in: 0...2.0,
                                step: 0.05
                            )
                            Text(L10n.Trim.crossfadeHelp(vm.lang))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Summary
                GroupBox(L10n.Crop.output(vm.lang)) {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(L10n.Trim.totalDuration(vm.lang)) {
                            Text(TimeFormatter.formatMMSS(vm.trimmedDuration))
                                .monospacedDigit()
                        }
                        LabeledContent(L10n.Trim.rangeCount(vm.lang)) {
                            Text("\(vm.project.trimSettings.ranges.count)")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                }

                // Trim bar visualization
                TrimBarView()
                    .frame(height: 36)
                    .padding(.top, 4)

                // Reset
                Button(L10n.Trim.resetTrim(vm.lang)) {
                    vm.resetTrim()
                }
                .controlSize(.small)
            }
        }
    }
}

/// One range row in the inspector — start/end controls + remove.
private struct TrimRangeBox: View {
    @EnvironmentObject var vm: ProjectViewModel
    let index: Int
    let range: TrimRange

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.Trim.rangeHeader(vm.lang, index: index))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button {
                        vm.seekToRange(id: range.id)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.Trim.playRange(vm.lang))
                    if vm.project.trimSettings.ranges.count > 1 {
                        Button {
                            vm.removeTrimRange(id: range.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.Trim.removeRange(vm.lang))
                    }
                }

                HStack {
                    Text(L10n.Ignore.startLabel(vm.lang))
                        .font(.caption)
                        .frame(width: 38, alignment: .leading)
                    Text(TimeFormatter.format(range.startTime))
                        .monospacedDigit()
                    Spacer()
                    Button(L10n.Ignore.current(vm.lang)) {
                        vm.setRangeStartToCurrent(id: range.id)
                    }
                    .controlSize(.small)
                }
                HStack(spacing: 4) {
                    Spacer().frame(width: 38)
                    Button("-1s") { vm.nudgeRangeStart(id: range.id, by: -1) }
                    Button("-0.1s") { vm.nudgeRangeStart(id: range.id, by: -0.1) }
                    Button("+0.1s") { vm.nudgeRangeStart(id: range.id, by: 0.1) }
                    Button("+1s") { vm.nudgeRangeStart(id: range.id, by: 1) }
                }
                .controlSize(.mini)

                HStack {
                    Text(L10n.Ignore.endLabel(vm.lang))
                        .font(.caption)
                        .frame(width: 38, alignment: .leading)
                    Text(TimeFormatter.format(range.endTime))
                        .monospacedDigit()
                    Spacer()
                    Button(L10n.Ignore.current(vm.lang)) {
                        vm.setRangeEndToCurrent(id: range.id)
                    }
                    .controlSize(.small)
                }
                HStack(spacing: 4) {
                    Spacer().frame(width: 38)
                    Button("-1s") { vm.nudgeRangeEnd(id: range.id, by: -1) }
                    Button("-0.1s") { vm.nudgeRangeEnd(id: range.id, by: -0.1) }
                    Button("+0.1s") { vm.nudgeRangeEnd(id: range.id, by: 0.1) }
                    Button("+1s") { vm.nudgeRangeEnd(id: range.id, by: 1) }
                }
                .controlSize(.mini)

                Text(L10n.Ignore.length(vm.lang, time: TimeFormatter.formatMMSS(range.duration)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Visual trim bar: shows every kept range over the source duration.
/// Drag handles for the first range stay editable; additional ranges are display-only
/// (use the inspector controls for fine adjustments).
struct TrimBarView: View {
    @EnvironmentObject var vm: ProjectViewModel
    private let handleWidth: CGFloat = 10
    private let handleHeight: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(vm.duration, 0.01)
            let playFrac = vm.currentTime / dur
            let ranges = vm.project.trimSettings.sortedRanges
            let firstStartFrac = ranges.first.map { $0.startTime / dur } ?? 0
            let firstEndFrac = ranges.first.map { $0.endTime / dur } ?? 1

            ZStack(alignment: .leading) {
                // Full duration background (darkened — represents trimmed-out region)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Waveform background
                if !vm.waveformPeaks.isEmpty {
                    WaveformView(
                        peaks: vm.waveformPeaks,
                        playFrac: playFrac,
                        startFrac: firstStartFrac,
                        endFrac: firstEndFrac
                    )
                    .padding(.vertical, 2)
                }

                // Darken everything first; then highlight kept ranges on top.
                Rectangle()
                    .fill(Color.black.opacity(0.3))

                ForEach(ranges) { range in
                    let s = max(0, range.startTime / dur)
                    let e = min(1, range.endTime / dur)
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: max(0, w * (e - s)))
                        .offset(x: w * s)
                    // Cut a transparent hole over this range (so the waveform shows through clearly)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: max(0, w * (e - s)))
                        .offset(x: w * s)
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                        )
                }

                // Playhead
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5)
                    .offset(x: w * playFrac)

                // Draggable handles for the FIRST range (kept for backwards-compat ergonomics).
                if let first = ranges.first {
                    let startFrac = first.startTime / dur
                    let endFrac = first.endTime / dur
                    TrimHandle(color: .green)
                        .offset(x: w * startFrac - handleWidth / 2)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let frac = max(0, min(value.location.x / w, 1))
                                    vm.setRangeStart(id: first.id, to: frac * dur)
                                }
                        )
                    TrimHandle(color: .red)
                        .offset(x: w * endFrac - handleWidth / 2)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let frac = max(0, min(value.location.x / w, 1))
                                    vm.setRangeEnd(id: first.id, to: frac * dur)
                                }
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

/// A draggable handle for the trim bar
struct TrimHandle: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 10, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.8), lineWidth: 1)
            )
            .contentShape(Rectangle().inset(by: -8))
            .cursor(.resizeLeftRight)
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
