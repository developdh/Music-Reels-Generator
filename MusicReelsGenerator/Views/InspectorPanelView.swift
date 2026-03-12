import SwiftUI

struct InspectorPanelView: View {
    @EnvironmentObject var vm: ProjectViewModel
    @State private var selectedTab: InspectorTab = .block

    enum InspectorTab: String, CaseIterable {
        case block = "Block"
        case trim = "Trim"
        case crop = "Crop"
        case style = "Style"
        case overlay = "Overlay"
        case info = "Info"
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    case .trim:
                        TrimInspectorView()
                    case .crop:
                        CropInspectorView()
                    case .style:
                        StyleInspectorView()
                    case .overlay:
                        MetadataOverlayInspectorView()
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

                Divider()

                GroupBox("Correction") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Set Start & Shift Following") {
                            vm.setStartTimeAndShiftFollowing()
                        }
                        .controlSize(.small)
                        .help("Set this block's start to current time and shift all following blocks by the same delta")

                        HStack(spacing: 4) {
                            Button("-0.5s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: -0.5) }
                            Button("-0.1s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: -0.1) }
                            Button("+0.1s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: 0.1) }
                            Button("+0.5s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: 0.5) }
                        }
                        .controlSize(.mini)

                        Toggle("Anchor", isOn: Binding(
                            get: { block.isAnchor },
                            set: { _ in vm.toggleAnchor(id: block.id) }
                        ))
                        .help("Anchor blocks are used as fixed timing references during alignment")
                    }
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

            GroupBox("Horizontal Position") {
                VStack(alignment: .leading, spacing: 8) {
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

                    Button("Center H") {
                        vm.project.cropSettings.horizontalOffset = 0
                        vm.isDirty = true
                    }
                    .controlSize(.small)
                }
            }

            GroupBox("Vertical Position") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("T")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: $vm.project.cropSettings.verticalOffset, in: -1...1)
                            .onChange(of: vm.project.cropSettings.verticalOffset) { _, _ in
                                vm.isDirty = true
                            }
                        Text("B")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Button("Center V") {
                        vm.project.cropSettings.verticalOffset = 0
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

    private var allFonts: [String] { FontUtility.allFamilies }
    private var jaDefaults: [String] { FontUtility.japaneseFamilies }
    private var koDefaults: [String] { FontUtility.koreanFamilies }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitle Style")
                .font(.headline)

            GroupBox("Japanese Font") {
                VStack(alignment: .leading, spacing: 8) {
                    FontFamilyPicker(
                        selection: $vm.project.subtitleStyle.japaneseFontFamily,
                        recommended: jaDefaults,
                        allFonts: allFonts
                    )

                    HStack {
                        Text("Size:")
                            .frame(width: 36, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.japaneseFontSize, in: 24...120, step: 1)
                        Text("\(Int(vm.project.subtitleStyle.japaneseFontSize))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    SubtitleColorPicker(
                        label: "Color:",
                        hexColor: $vm.project.subtitleStyle.japaneseTextColorHex
                    )
                }
            }

            GroupBox("Korean Font") {
                VStack(alignment: .leading, spacing: 8) {
                    FontFamilyPicker(
                        selection: $vm.project.subtitleStyle.koreanFontFamily,
                        recommended: koDefaults,
                        allFonts: allFonts
                    )

                    HStack {
                        Text("Size:")
                            .frame(width: 36, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.koreanFontSize, in: 20...100, step: 1)
                        Text("\(Int(vm.project.subtitleStyle.koreanFontSize))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    SubtitleColorPicker(
                        label: "Color:",
                        hexColor: $vm.project.subtitleStyle.koreanTextColorHex
                    )
                }
            }

            GroupBox("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Outline:")
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.outlineWidth, in: 0...8, step: 0.5)
                        Text("\(String(format: "%.1f", vm.project.subtitleStyle.outlineWidth))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }

                    Toggle("Shadow", isOn: $vm.project.subtitleStyle.shadowEnabled)
                }
            }

            GroupBox("Position") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bottom:")
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.bottomMargin, in: 50...960, step: 5)
                        Text("\(Int(vm.project.subtitleStyle.bottomMargin))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    HStack {
                        Text("Gap:")
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.lineSpacing, in: 0...40, step: 1)
                        Text("\(Int(vm.project.subtitleStyle.lineSpacing))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }
                }
            }
        }
        .onChange(of: vm.project.subtitleStyle) { _, _ in
            vm.isDirty = true
        }
    }
}

/// A font picker that shows recommended fonts first, then all system fonts
struct FontFamilyPicker: View {
    @Binding var selection: String
    let recommended: [String]
    let allFonts: [String]

    var body: some View {
        Picker("Font", selection: $selection) {
            if !recommended.isEmpty {
                Section("Recommended") {
                    ForEach(recommended, id: \.self) { font in
                        Text(font)
                            .font(.custom(font, size: 13))
                            .tag(font)
                    }
                }
                Divider()
            }

            Section("All Fonts") {
                ForEach(allFonts, id: \.self) { font in
                    Text(font).tag(font)
                }
            }
        }
        .labelsHidden()
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

// MARK: - Trim Inspector

struct TrimInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trim Settings")
                .font(.headline)

            if !vm.project.hasVideo {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("Import a video first")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Trim Start
                GroupBox("Trim Start") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(TimeFormatter.format(vm.project.trimSettings.startTime))
                                .monospacedDigit()
                                .font(.title3)
                            Spacer()
                            Button("Set to Current") {
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
                GroupBox("Trim End") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(TimeFormatter.format(vm.project.trimSettings.endTime))
                                .monospacedDigit()
                                .font(.title3)
                            Spacer()
                            Button("Set to Current") {
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
                GroupBox("Output") {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent("Duration") {
                            Text(TimeFormatter.formatMMSS(vm.trimmedDuration))
                                .monospacedDigit()
                        }
                        LabeledContent("Range") {
                            Text("\(TimeFormatter.format(vm.project.trimSettings.startTime)) — \(TimeFormatter.format(vm.project.trimSettings.endTime))")
                                .monospacedDigit()
                                .font(.caption)
                        }
                    }
                    .font(.caption)
                }

                // Trim bar visualization
                TrimBarView()
                    .frame(height: 32)
                    .padding(.top, 4)

                // Reset
                Button("Reset Trim (Full Duration)") {
                    vm.resetTrim()
                }
                .controlSize(.small)
            }
        }
    }
}

/// A simple visual trim bar showing the selected range
struct TrimBarView: View {
    @EnvironmentObject var vm: ProjectViewModel

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

                // Trim start marker
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2)
                    .offset(x: w * startFrac)

                // Trim end marker
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: max(0, w * endFrac - 2))

                // Playhead
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1.5)
                    .offset(x: w * playFrac)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

// MARK: - Metadata Overlay Inspector

struct MetadataOverlayInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    private var allFonts: [String] { FontUtility.allFamilies }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Title / Artist Overlay")
                .font(.headline)

            Toggle("Enable Overlay", isOn: $vm.project.metadataOverlay.isEnabled)

            if vm.project.metadataOverlay.isEnabled {
                GroupBox("Title") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Song title", text: $vm.project.metadataOverlay.titleText)
                            .textFieldStyle(.roundedBorder)

                        Picker("Font", selection: $vm.project.metadataOverlay.titleFontFamily) {
                            ForEach(allFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Text("Size:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.titleFontSize, in: 20...100, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.titleFontSize))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        SubtitleColorPicker(
                            label: "Color:",
                            hexColor: $vm.project.metadataOverlay.titleTextColorHex
                        )
                    }
                }

                GroupBox("Artist") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Artist name", text: $vm.project.metadataOverlay.artistText)
                            .textFieldStyle(.roundedBorder)

                        Picker("Font", selection: $vm.project.metadataOverlay.artistFontFamily) {
                            ForEach(allFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Text("Size:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.artistFontSize, in: 16...72, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.artistFontSize))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        SubtitleColorPicker(
                            label: "Color:",
                            hexColor: $vm.project.metadataOverlay.artistTextColorHex
                        )
                    }
                }

                GroupBox("Background") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Opacity:")
                                .frame(width: 52, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.backgroundOpacity, in: 0...1, step: 0.05)
                            Text("\(Int(vm.project.metadataOverlay.backgroundOpacity * 100))%")
                                .monospacedDigit()
                                .frame(width: 36)
                        }

                        HStack {
                            Text("Radius:")
                                .frame(width: 52, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.cornerRadius, in: 0...30, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.cornerRadius))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                }

                GroupBox("Position") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.topMargin, in: 20...400, step: 5)
                            Text("\(Int(vm.project.metadataOverlay.topMargin))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        HStack {
                            Text("Left:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.leftMargin, in: 20...300, step: 5)
                            Text("\(Int(vm.project.metadataOverlay.leftMargin))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }
                    }
                }

                GroupBox("Padding") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("H:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.horizontalPadding, in: 8...50, step: 2)
                            Text("\(Int(vm.project.metadataOverlay.horizontalPadding))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }

                        HStack {
                            Text("V:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.verticalPadding, in: 6...40, step: 2)
                            Text("\(Int(vm.project.metadataOverlay.verticalPadding))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }

                        HStack {
                            Text("Gap:")
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.lineSpacing, in: 0...20, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.lineSpacing))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                }
            }
        }
        .onChange(of: vm.project.metadataOverlay) { _, _ in
            vm.isDirty = true
        }
    }
}

// MARK: - Subtitle Color Picker

struct SubtitleColorPicker: View {
    let label: String
    @Binding var hexColor: String

    private static let presets: [(String, String)] = [
        ("White", "#FFFFFF"),
        ("Cyan", "#E0FFFF"),
        ("Yellow", "#FFFACD"),
        ("Mint", "#BDFCC9"),
        ("Pink", "#FFB6C1"),
    ]

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 36, alignment: .trailing)

            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: hexColor) },
                    set: { hexColor = $0.toHex() }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 28)

            ForEach(Self.presets, id: \.1) { name, hex in
                Button {
                    hexColor = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(
                            Circle().stroke(hex == hexColor ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: hex == hexColor ? 2 : 1)
                        )
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(name)
            }
        }
    }
}
