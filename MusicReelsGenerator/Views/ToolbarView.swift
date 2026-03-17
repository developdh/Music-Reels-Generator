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
                Label(L10n.Toolbar.importVideo(vm.lang), systemImage: "film.fill")
            }

            Button {
                vm.showURLImportSheet = true
            } label: {
                Label(L10n.Toolbar.urlImport(vm.lang), systemImage: "link.badge.plus")
            }

            Divider().frame(height: 20)

            // Primary language
            Picker("", selection: $vm.project.primaryLanguage) {
                ForEach(PrimaryLanguage.allCases) { lang in
                    Text(L10n.PrimaryLang.displayName(lang, vm.lang)).tag(lang)
                }
            }
            .frame(width: 120)
            .help(L10n.Toolbar.languageHelp(vm.lang))
            .onChange(of: vm.project.primaryLanguage) { _, _ in
                vm.project.touch()
                vm.isDirty = true
            }

            // Alignment quality mode
            Picker("", selection: $vm.alignmentQualityMode) {
                ForEach(AlignmentQualityMode.allCases) { mode in
                    HStack {
                        Text(mode.rawValue)
                        if mode.isExperimental && !vm.advancedPipelineAvailable {
                            Text("*").foregroundColor(.orange)
                        }
                    }.tag(mode)
                }
            }
            .frame(width: 140)
            .help(alignmentPickerHelp)

            // Alignment
            Button {
                Task { await vm.runAutoAlignment() }
            } label: {
                if vm.isAligning {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                    Text(L10n.Toolbar.aligning(vm.lang))
                } else {
                    Label(L10n.Toolbar.autoAlign(vm.lang), systemImage: "waveform.badge.magnifyingglass")
                }
            }
            .disabled(!vm.project.hasVideo || !vm.project.hasLyrics || vm.isAligning
                      || (vm.alignmentQualityMode.usesLegacyPipeline && !vm.whisperAvailable)
                      || (vm.alignmentQualityMode.usesAdvancedPipeline && !vm.advancedPipelineAvailable))

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
                ToolStatusBadge(name: "Python (Exp)", available: vm.advancedPipelineAvailable)
            }

            Divider().frame(height: 20)

            // Export
            Button {
                exportVideo()
            } label: {
                Label(L10n.Toolbar.export(vm.lang), systemImage: "square.and.arrow.up.fill")
            }
            .disabled(!vm.project.isReadyForExport)

            Divider().frame(height: 20)

            // Open
            Button {
                openProject()
            } label: {
                Label(L10n.Toolbar.open(vm.lang), systemImage: "folder")
            }

            // Save
            Button {
                if !vm.saveProject() {
                    showSaveAsPanel()
                }
            } label: {
                Label(L10n.Toolbar.save(vm.lang), systemImage: "square.and.arrow.down")
            }

            Divider().frame(height: 20)

            Picker("", selection: $vm.uiLanguage) {
                ForEach(UILanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .frame(width: 80)
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

    private var alignmentPickerHelp: String {
        if vm.alignmentQualityMode.isExperimental && !vm.advancedPipelineAvailable {
            return L10n.Toolbar.experimentalNotAvailable(vm.lang)
        }
        return vm.alignmentQualityMode.description
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
