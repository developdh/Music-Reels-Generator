import SwiftUI

struct PlaybackControlsView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Scrubber / timeline
            HStack(spacing: 8) {
                Text(TimeFormatter.format(vm.currentTime))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)

                Slider(value: Binding(
                    get: { vm.currentTime },
                    set: { vm.seek(to: $0) }
                ), in: 0...max(vm.duration, 0.01))
                .disabled(vm.player == nil)

                Text(TimeFormatter.format(vm.duration))
                    .font(.caption)
                    .monospacedDigit()
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
                .help("Back 5s (Cmd+Left)")

                // Step back 1s
                Button { vm.stepBackward(seconds: 1) } label: {
                    Image(systemName: "gobackward")
                }
                .help("Back 1s")

                // Play/Pause
                Button { vm.togglePlayback() } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .keyboardShortcut(.space, modifiers: [])
                .help("Play/Pause (Space)")

                // Step forward 1s
                Button { vm.stepForward(seconds: 1) } label: {
                    Image(systemName: "goforward")
                }
                .help("Forward 1s")

                // Step forward 5s
                Button { vm.stepForward(seconds: 5) } label: {
                    Image(systemName: "goforward.5")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .help("Forward 5s (Cmd+Right)")

                Divider().frame(height: 20)

                // Set timing buttons
                Button {
                    vm.setStartTimeToCurrent()
                } label: {
                    Label("Set Start", systemImage: "arrow.right.to.line")
                }
                .disabled(vm.selectedBlockID == nil)
                .keyboardShortcut("[", modifiers: .command)
                .help("Set block start to current time (Cmd+[)")

                Button {
                    vm.setEndTimeToCurrent()
                } label: {
                    Label("Set End", systemImage: "arrow.left.to.line")
                }
                .disabled(vm.selectedBlockID == nil)
                .keyboardShortcut("]", modifiers: .command)
                .help("Set block end to current time (Cmd+])")
            }
            .disabled(vm.player == nil)
        }
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
