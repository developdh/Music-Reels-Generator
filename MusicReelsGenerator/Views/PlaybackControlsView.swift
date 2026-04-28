import SwiftUI

struct PlaybackControlsView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Scrubber / timeline with trim markers
            HStack(spacing: 8) {
                Text(TimeFormatter.format(vm.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)

                WaveformScrubberView(
                    peaks: vm.waveformPeaks,
                    duration: vm.duration,
                    currentTime: vm.currentTime,
                    trimStart: vm.project.trimSettings.startTime,
                    trimEnd: vm.project.trimSettings.endTime,
                    isTrimActive: vm.project.trimSettings.isActive(sourceDuration: vm.duration),
                    isEnabled: vm.player != nil,
                    onSeek: { vm.seek(to: $0) }
                )
                .frame(height: 36)

                VStack(alignment: .leading, spacing: 0) {
                    Text(TimeFormatter.format(vm.duration))
                        .font(.caption)
                        .monospacedDigit()
                    if vm.project.trimSettings.isActive(sourceDuration: vm.duration) {
                        Text("[\(TimeFormatter.formatMMSS(vm.trimmedDuration))]")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                            .monospacedDigit()
                    }
                }
                .frame(width: 60, alignment: .leading)
            }
            .padding(.horizontal, 16)

            // Playback buttons
            HStack(spacing: 16) {
                // Step back 5s
                Button { vm.stepBackward(seconds: 5) } label: {
                    Image(systemName: "gobackward.5")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .help(L10n.Playback.back5s(vm.lang))

                // Step back 1s
                Button { vm.stepBackward(seconds: 1) } label: {
                    Image(systemName: "gobackward")
                }
                .help(L10n.Playback.back1s(vm.lang))

                // Play/Pause
                Button { vm.togglePlayback() } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help(L10n.Playback.playPause(vm.lang))

                // Step forward 1s
                Button { vm.stepForward(seconds: 1) } label: {
                    Image(systemName: "goforward")
                }
                .help(L10n.Playback.forward1s(vm.lang))

                // Step forward 5s
                Button { vm.stepForward(seconds: 5) } label: {
                    Image(systemName: "goforward.5")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help(L10n.Playback.forward5s(vm.lang))

                Divider().frame(height: 20)

                // Set timing buttons
                Button {
                    vm.setStartTimeToCurrent()
                } label: {
                    Label(L10n.Playback.setStart(vm.lang), systemImage: "arrow.right.to.line")
                }
                .disabled(vm.selectedBlockID == nil)
                .keyboardShortcut("[", modifiers: .command)
                .help(L10n.Playback.setStartHelp(vm.lang))

                Button {
                    vm.setEndTimeToCurrent()
                } label: {
                    Label(L10n.Playback.setEnd(vm.lang), systemImage: "arrow.left.to.line")
                }
                .disabled(vm.selectedBlockID == nil)
                .keyboardShortcut("]", modifiers: .command)
                .help(L10n.Playback.setEndHelp(vm.lang))

                // Hidden: block navigation (Cmd+Up/Down)
                Button { vm.selectPreviousBlock() } label: { EmptyView() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)

                Button { vm.selectNextBlock() } label: { EmptyView() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
            .disabled(vm.player == nil)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
