import SwiftUI
import UniformTypeIdentifiers

struct ToolbarView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Import video
            Button {
                importVideo()
            } label: {
                Label("Import Video", systemImage: "film.fill")
            }

            Divider().frame(height: 20)

            // Alignment
            Button {
                Task { await vm.runAutoAlignment() }
            } label: {
                if vm.isAligning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    Text("Aligning...")
                } else {
                    Label("Auto-Align", systemImage: "waveform.badge.magnifyingglass")
                }
            }
            .disabled(!vm.project.hasVideo || !vm.project.hasLyrics || vm.isAligning)

            if vm.isAligning {
                Text(vm.alignmentProgress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Tool status indicators
            HStack(spacing: 8) {
                ToolStatusBadge(name: "FFmpeg", available: vm.ffmpegAvailable)
                ToolStatusBadge(name: "Whisper", available: vm.whisperAvailable)
            }

            Divider().frame(height: 20)

            // Export
            Button {
                exportVideo()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up.fill")
            }
            .disabled(!vm.project.isReadyForExport)

            Divider().frame(height: 20)

            // Open
            Button {
                openProject()
            } label: {
                Label("Open", systemImage: "folder")
            }

            // Save
            Button {
                if !vm.saveProject() {
                    showSaveAsPanel()
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
        }
    }

    private func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            Task { await vm.importVideo(url: url) }
        }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: ProjectPersistenceService.fileExtension)!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            vm.loadProject(from: url)
        }
    }

    private func showSaveAsPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: ProjectPersistenceService.fileExtension)!]
        panel.nameFieldStringValue = "\(vm.project.title).\(ProjectPersistenceService.fileExtension)"
        if panel.runModal() == .OK, let url = panel.url {
            vm.saveProjectAs(to: url)
        }
    }

    private func exportVideo() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(vm.project.title)_vertical.mp4"

        if panel.runModal() == .OK, let url = panel.url {
            Task { await vm.exportVideo(to: url) }
        }
    }
}

struct ToolStatusBadge: View {
    let name: String
    let available: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(available ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
