import SwiftUI

struct InfoInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Info.projectInfo(vm.lang))
                .font(.headline)

            GroupBox(L10n.Info.project(vm.lang)) {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent(L10n.Info.title(vm.lang)) {
                        TextField(L10n.Info.title(vm.lang), text: $vm.project.title)
                            .textFieldStyle(.plain)
                            .onChange(of: vm.project.title) { _, _ in
                                vm.isDirty = true
                            }
                    }
                    LabeledContent(L10n.Info.created(vm.lang)) {
                        Text(vm.project.createdAt, style: .date)
                    }
                }
            }

            if vm.project.hasVideo {
                GroupBox(L10n.Info.video(vm.lang)) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let path = vm.project.sourceVideoPath {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        let meta = vm.project.videoMetadata
                        LabeledContent(L10n.Info.resolution(vm.lang)) {
                            Text("\(meta.width)x\(meta.height) (\(meta.aspectRatioString))")
                        }
                        LabeledContent(L10n.Trim.duration(vm.lang)) {
                            Text(TimeFormatter.formatMMSS(meta.duration))
                        }
                        LabeledContent(L10n.Info.frameRate(vm.lang)) {
                            Text(String(format: "%.1f fps", meta.frameRate))
                        }
                        if meta.fileSize > 0 {
                            LabeledContent(L10n.Info.fileSize(vm.lang)) {
                                Text(ByteCountFormatter.string(fromByteCount: meta.fileSize, countStyle: .file))
                            }
                        }
                    }
                    .font(.caption)
                }
            }

            GroupBox(L10n.Info.tools(vm.lang)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("FFmpeg:")
                        Text(vm.ffmpegAvailable ? L10n.Info.found(vm.lang) : L10n.Info.notFound(vm.lang))
                            .foregroundColor(vm.ffmpegAvailable ? .green : .red)
                    }
                    HStack {
                        Text("whisper.cpp:")
                        Text(vm.whisperAvailable ? L10n.Info.found(vm.lang) : L10n.Info.notFound(vm.lang))
                            .foregroundColor(vm.whisperAvailable ? .green : .red)
                    }

                    if !vm.ffmpegAvailable || !vm.whisperAvailable {
                        Text(L10n.Info.installMissing(vm.lang))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        if !vm.ffmpegAvailable {
                            Text("brew install ffmpeg")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if !vm.whisperAvailable {
                            Text("brew install whisper-cpp")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }

                    Button(L10n.Info.recheckTools(vm.lang)) {
                        vm.checkToolAvailability()
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
    }
}
