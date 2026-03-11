import SwiftUI

struct InspectorPanelView: View {
    @EnvironmentObject var vm: ProjectViewModel
    @State private var selectedTab: InspectorTab = .block

    enum InspectorTab: String, CaseIterable {
        case block = "Block"
        case crop = "Crop"
        case style = "Style"
        case info = "Info"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch selectedTab {
                    case .block:
                        BlockInspectorView()
                    case .crop:
                        CropInspectorView()
                    case .style:
                        StyleInspectorView()
                    case .info:
                        InfoInspectorView()
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Block Inspector

struct BlockInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        if let block = vm.selectedBlock, let idx = vm.selectedBlockIndex {
            VStack(alignment: .leading, spacing: 12) {
                Text("Block #\(idx + 1)")
                    .font(.headline)

                GroupBox("Japanese") {
                    Text(block.japanese)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                GroupBox("Korean") {
                    Text(block.korean)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                GroupBox("Timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Start:")
                                .frame(width: 40, alignment: .trailing)
                            if let start = block.startTime {
                                Text(TimeFormatter.format(start))
                                    .monospacedDigit()
                            } else {
                                Text("Not set")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Set Now") {
                                vm.setStartTimeToCurrent()
                            }
                            .controlSize(.small)
                        }

                        HStack {
                            Text("End:")
                                .frame(width: 40, alignment: .trailing)
                            if let end = block.endTime {
                                Text(TimeFormatter.format(end))
                                    .monospacedDigit()
                            } else {
                                Text("Not set")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Set Now") {
                                vm.setEndTimeToCurrent()
                            }
                            .controlSize(.small)
                        }

                        if let confidence = block.confidence {
                            HStack {
                                Text("Confidence:")
                                ConfidenceBadge(confidence: confidence, isManual: block.isManuallyAdjusted)
                            }
                        }
                    }
                }

                HStack {
                    Button("Seek to Start") {
                        if let start = block.startTime {
                            vm.seek(to: start)
                        }
                    }
                    .disabled(block.startTime == nil)

                    Button("Seek to End") {
                        if let end = block.endTime {
                            vm.seek(to: end)
                        }
                    }
                    .disabled(block.endTime == nil)
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Select a lyric block")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Crop Inspector

struct CropInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Crop Settings")
                .font(.headline)

            GroupBox("Mode") {
                Picker("Crop Mode", selection: $vm.project.cropSettings.mode) {
                    ForEach(CropMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.project.cropSettings.mode) { _, _ in
                    vm.isDirty = true
                }
            }

            GroupBox("Position") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Horizontal Offset")
                        .font(.caption)
                    HStack {
                        Text("L")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: $vm.project.cropSettings.horizontalOffset, in: -1...1)
                            .onChange(of: vm.project.cropSettings.horizontalOffset) { _, _ in
                                vm.isDirty = true
                            }
                        Text("R")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Button("Center") {
                        vm.project.cropSettings.horizontalOffset = 0
                        vm.isDirty = true
                    }
                    .controlSize(.small)
                }
            }

            GroupBox("Output") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Resolution: \(vm.project.cropSettings.outputWidth)x\(vm.project.cropSettings.outputHeight)")
                        .font(.caption)
                    Text("Aspect: 9:16 (Reels/Shorts)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Style Inspector

struct StyleInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitle Style")
                .font(.headline)

            GroupBox("Font Sizes") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Japanese:")
                            .frame(width: 70, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.japaneseFontSize, in: 20...80)
                        Text("\(Int(vm.project.subtitleStyle.japaneseFontSize))")
                            .monospacedDigit()
                            .frame(width: 30)
                    }

                    HStack {
                        Text("Korean:")
                            .frame(width: 70, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.koreanFontSize, in: 16...60)
                        Text("\(Int(vm.project.subtitleStyle.koreanFontSize))")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                }
            }

            GroupBox("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Outline Width:")
                        Slider(value: $vm.project.subtitleStyle.outlineWidth, in: 0...8)
                        Text("\(Int(vm.project.subtitleStyle.outlineWidth))")
                            .frame(width: 20)
                    }

                    Toggle("Shadow", isOn: $vm.project.subtitleStyle.shadowEnabled)
                }
            }

            GroupBox("Position") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bottom Margin:")
                        Slider(value: $vm.project.subtitleStyle.bottomMargin, in: 50...500)
                        Text("\(Int(vm.project.subtitleStyle.bottomMargin))")
                            .frame(width: 30)
                    }

                    HStack {
                        Text("Line Spacing:")
                        Slider(value: $vm.project.subtitleStyle.lineSpacing, in: 0...30)
                        Text("\(Int(vm.project.subtitleStyle.lineSpacing))")
                            .frame(width: 20)
                    }
                }
            }
        }
        .onChange(of: vm.project.subtitleStyle) { _, _ in
            vm.isDirty = true
        }
    }
}

// MARK: - Info Inspector

struct InfoInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Info")
                .font(.headline)

            GroupBox("Project") {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("Title") {
                        TextField("Title", text: $vm.project.title)
                            .textFieldStyle(.plain)
                            .onChange(of: vm.project.title) { _, _ in
                                vm.isDirty = true
                            }
                    }
                    LabeledContent("Created") {
                        Text(vm.project.createdAt, style: .date)
                    }
                }
            }

            if vm.project.hasVideo {
                GroupBox("Video") {
                    VStack(alignment: .leading, spacing: 4) {
                        if let path = vm.project.sourceVideoPath {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        let meta = vm.project.videoMetadata
                        LabeledContent("Resolution") {
                            Text("\(meta.width)x\(meta.height) (\(meta.aspectRatioString))")
                        }
                        LabeledContent("Duration") {
                            Text(TimeFormatter.formatMMSS(meta.duration))
                        }
                        LabeledContent("Frame Rate") {
                            Text(String(format: "%.1f fps", meta.frameRate))
                        }
                        if meta.fileSize > 0 {
                            LabeledContent("File Size") {
                                Text(ByteCountFormatter.string(fromByteCount: meta.fileSize, countStyle: .file))
                            }
                        }
                    }
                    .font(.caption)
                }
            }

            GroupBox("Tools") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("FFmpeg:")
                        Text(vm.ffmpegAvailable ? "Found" : "Not found")
                            .foregroundColor(vm.ffmpegAvailable ? .green : .red)
                    }
                    HStack {
                        Text("whisper.cpp:")
                        Text(vm.whisperAvailable ? "Found" : "Not found")
                            .foregroundColor(vm.whisperAvailable ? .green : .red)
                    }

                    if !vm.ffmpegAvailable || !vm.whisperAvailable {
                        Text("Install missing tools via Homebrew:")
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

                    Button("Recheck Tools") {
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
