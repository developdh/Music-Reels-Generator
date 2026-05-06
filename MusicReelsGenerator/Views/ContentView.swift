import SwiftUI

struct ContentView: View {
    @EnvironmentObject var vm: ProjectViewModel
    @State private var isDropTargeted = false

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
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 400)
            }

            Divider()

            // Status bar
            StatusBarView()
                .frame(height: 28)
        }
        .alert(L10n.Common.error(vm.lang), isPresented: $vm.showError) {
            Button(L10n.Common.ok(vm.lang)) { vm.showError = false }
        } message: {
            Text(vm.errorMessage ?? L10n.Common.unknownError(vm.lang))
        }
        .sheet(isPresented: $vm.showURLImportSheet) {
            URLImportSheet()
                .environmentObject(vm)
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    Color.accentColor.opacity(0.08)
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 44))
                        Text(L10n.DragDrop.hint(vm.lang))
                            .font(.headline)
                    }
                    .foregroundColor(.accentColor)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.accentColor, lineWidth: isDropTargeted ? 3 : 0)
                .allowsHitTesting(false)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            vm.handleDroppedURL(url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }
}
