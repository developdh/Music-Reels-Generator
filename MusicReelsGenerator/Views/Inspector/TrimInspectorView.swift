import SwiftUI
import AppKit

struct TrimInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Trim.settings(vm.lang))
                .font(.headline)

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
                // Trim Start
                GroupBox(L10n.Trim.trimStart(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(TimeFormatter.format(vm.project.trimSettings.startTime))
                                .monospacedDigit()
                                .font(.title3)
                            Spacer()
                            Button(L10n.Trim.setToCurrent(vm.lang)) {
                                vm.setTrimStartToCurrent()
                            }
                            .controlSize(.small)
                        }

                        HStack(spacing: 4) {
                            Button("-1s") { vm.nudgeTrimStart(by: -1) }
                            Button("-0.1s") { vm.nudgeTrimStart(by: -0.1) }
                            Button("+0.1s") { vm.nudgeTrimStart(by: 0.1) }
                            Button("+1s") { vm.nudgeTrimStart(by: 1) }
                        }
                        .controlSize(.mini)
                    }
                }

                // Trim End
                GroupBox(L10n.Trim.trimEnd(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(TimeFormatter.format(vm.project.trimSettings.endTime))
                                .monospacedDigit()
                                .font(.title3)
                            Spacer()
                            Button(L10n.Trim.setToCurrent(vm.lang)) {
                                vm.setTrimEndToCurrent()
                            }
                            .controlSize(.small)
                        }

                        HStack(spacing: 4) {
                            Button("-1s") { vm.nudgeTrimEnd(by: -1) }
                            Button("-0.1s") { vm.nudgeTrimEnd(by: -0.1) }
                            Button("+0.1s") { vm.nudgeTrimEnd(by: 0.1) }
                            Button("+1s") { vm.nudgeTrimEnd(by: 1) }
                        }
                        .controlSize(.mini)
                    }
                }

                // Summary
                GroupBox(L10n.Crop.output(vm.lang)) {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(L10n.Trim.duration(vm.lang)) {
                            Text(TimeFormatter.formatMMSS(vm.trimmedDuration))
                                .monospacedDigit()
                        }
                        LabeledContent(L10n.Trim.range(vm.lang)) {
                            Text("\(TimeFormatter.format(vm.project.trimSettings.startTime)) — \(TimeFormatter.format(vm.project.trimSettings.endTime))")
                                .monospacedDigit()
                                .font(.caption)
                        }
                    }
                    .font(.caption)
                }

                // Trim bar visualization (drag green/red handles to adjust)
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

/// Interactive trim bar with draggable start/end handles
struct TrimBarView: View {
    @EnvironmentObject var vm: ProjectViewModel
    private let handleWidth: CGFloat = 10
    private let handleHeight: CGFloat = 32

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(vm.duration, 0.01)
            let startFrac = vm.project.trimSettings.startTime / dur
            let endFrac = vm.project.trimSettings.endTime / dur
            let playFrac = vm.currentTime / dur

            ZStack(alignment: .leading) {
                // Full duration background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Trimmed-out region (before start)
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: max(0, w * startFrac))

                // Trimmed-out region (after end)
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: max(0, w * (1 - endFrac)))
                    .offset(x: w * endFrac)

                // Active trim region
                Rectangle()
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(width: max(0, w * (endFrac - startFrac)))
                    .offset(x: w * startFrac)

                // Playhead
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5)
                    .offset(x: w * playFrac)

                // Draggable start handle
                TrimHandle(color: .green)
                    .offset(x: w * startFrac - handleWidth / 2)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let frac = max(0, min(value.location.x / w, 1))
                                vm.setTrimStart(to: frac * dur)
                            }
                    )

                // Draggable end handle
                TrimHandle(color: .red)
                    .offset(x: w * endFrac - handleWidth / 2)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let frac = max(0, min(value.location.x / w, 1))
                                vm.setTrimEnd(to: frac * dur)
                            }
                    )
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
