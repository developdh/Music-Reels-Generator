import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content
            HSplitView {
                // Left panel: Lyrics
                LyricsPanelView()
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

                // Center: Video preview + playback
                VStack(spacing: 0) {
                    VideoPreviewView()
                    Divider()
                    PlaybackControlsView()
                        .frame(height: 80)
                }
                .frame(minWidth: 400)

                // Right panel: Inspector
                InspectorPanelView()
                    .frame(minWidth: 250, idealWidth: 280, maxWidth: 350)
            }

            Divider()

            // Status bar
            StatusBarView()
                .frame(height: 28)
        }
        .alert("Error", isPresented: $vm.showError) {
            Button("OK") { vm.showError = false }
        } message: {
            Text(vm.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $vm.showURLImportSheet) {
            URLImportSheet()
                .environmentObject(vm)
        }
    }
}
