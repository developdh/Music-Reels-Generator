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
        case ignore = "Ignore"
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
                    case .ignore:
                        IgnoreRegionsInspectorView()
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
                    }
                }

                GroupBox("앵커 & 재보정") {
                    VStack(alignment: .leading, spacing: 8) {
                        // Anchor controls
                        HStack {
                            if block.isUserAnchor {
                                Label("사용자 앵커", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                                Button("앵커 해제") {
                                    vm.unsetAnchor(id: block.id)
                                }
                                .controlSize(.small)
                            } else if block.isAnchor {
                                Label("자동 앵커", systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button("사용자 앵커로 승격") {
                                    vm.setAnchor(id: block.id)
                                }
                                .controlSize(.small)
                                .help("이 자동 앵커를 사용자 앵커로 승격하여 재보정 기준점으로 사용합니다")
                            } else {
                                Button("이 줄을 앵커로 고정") {
                                    vm.setAnchor(id: block.id)
                                }
                                .controlSize(.small)
                                .help("이 블록의 타이밍을 신뢰할 수 있는 기준점으로 고정합니다")
                            }
                        }

                        if block.isManuallyAdjusted && !block.isUserAnchor {
                            HStack(spacing: 4) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption2)
                                Text("수동 조정됨 — 앵커로 고정 권장")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        // Piecewise correction between anchors
                        Button("이전 앵커 ~ 다음 앵커 재보정") {
                            vm.correctBetweenSurroundingAnchors()
                        }
                        .controlSize(.small)
                        .disabled(!vm.hasSurroundingAnchors)
                        .help("양쪽 앵커 사이의 블록 타이밍을 비례 배분합니다")

                        Button("전체 앵커 구간 재보정") {
                            vm.correctBetweenAllAnchors()
                        }
                        .controlSize(.small)
                        .disabled(vm.anchorCount < 2)
                        .help("모든 앵커 쌍 사이의 블록 타이밍을 재보정합니다")

                        Divider()

                        // Local re-alignment with legacy engine
                        Button("이 구간 재정렬 (레거시 엔진)") {
                            Task { await vm.localRealignSurroundingRegion() }
                        }
                        .controlSize(.small)
                        .disabled(!vm.project.hasVideo || !vm.whisperAvailable || vm.isAligning)
                        .help("이전~다음 앵커 사이를 whisper-cpp로 다시 정렬합니다")
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

            GroupBox("Zoom") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("1x")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Slider(value: $vm.project.cropSettings.zoomScale, in: 1.0...3.0, step: 0.05)
                            .onChange(of: vm.project.cropSettings.zoomScale) { _, _ in
                                vm.isDirty = true
                            }
                        Text("\(String(format: "%.1f", vm.project.cropSettings.zoomScale))x")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 30)
                    }

                    if vm.project.cropSettings.zoomScale > 1.0 {
                        Button("Reset Zoom") {
                            vm.project.cropSettings.zoomScale = 1.0
                            vm.isDirty = true
                        }
                        .controlSize(.small)
                    }
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
    @ObservedObject private var presetStore = StylePresetStore.shared
    @State private var showSaveSheet = false
    @State private var showManageSheet = false

    private var allFonts: [String] { FontUtility.allFamilies }
    private var jaDefaults: [String] { FontUtility.japaneseFamilies }
    private var koDefaults: [String] { FontUtility.koreanFamilies }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitle Style")
                .font(.headline)

            // Style Presets
            GroupBox("프리셋") {
                VStack(alignment: .leading, spacing: 8) {
                    if !presetStore.presets.isEmpty {
                        HStack {
                            Menu {
                                ForEach(presetStore.presets) { preset in
                                    Button(preset.name) {
                                        vm.applyPreset(preset)
                                    }
                                }
                            } label: {
                                Label("프리셋 적용", systemImage: "paintbrush")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text("저장된 프리셋 없음")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button("현재 스타일 저장") {
                            showSaveSheet = true
                        }
                        .controlSize(.small)

                        if !presetStore.presets.isEmpty {
                            Button("관리") {
                                showManageSheet = true
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                SavePresetSheet(vm: vm, presetStore: presetStore)
            }
            .sheet(isPresented: $showManageSheet) {
                ManagePresetsSheet(vm: vm, presetStore: presetStore)
            }

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

                // Trim bar visualization (drag green/red handles to adjust)
                TrimBarView()
                    .frame(height: 36)
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
                .lineLimit(1)
                .fixedSize()
                .frame(width: 42, alignment: .trailing)

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

// MARK: - Save Preset Sheet

struct SavePresetSheet: View {
    @ObservedObject var vm: ProjectViewModel
    @ObservedObject var presetStore: StylePresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var presetName: String = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("현재 스타일을 프리셋으로 저장")
                .font(.headline)

            TextField("프리셋 이름", text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { save() }

            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text("자막 스타일과 오버레이 스타일이 저장됩니다.\n곡 제목/아티스트 텍스트는 포함되지 않습니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
    }

    private func save() {
        let trimmed = presetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorText = "이름을 입력하세요."
            return
        }
        if presetStore.nameExists(trimmed) {
            errorText = "이미 같은 이름의 프리셋이 있습니다."
            return
        }
        vm.saveCurrentStyleAsPreset(name: trimmed)
        dismiss()
    }
}

// MARK: - Manage Presets Sheet

struct ManagePresetsSheet: View {
    @ObservedObject var vm: ProjectViewModel
    @ObservedObject var presetStore: StylePresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    @State private var editName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("프리셋 관리")
                    .font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if presetStore.presets.isEmpty {
                VStack(spacing: 8) {
                    Text("저장된 프리셋이 없습니다.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(presetStore.presets) { preset in
                        PresetRow(
                            preset: preset,
                            isEditing: editingID == preset.id,
                            editName: editingID == preset.id ? $editName : .constant(""),
                            onApply: {
                                vm.applyPreset(preset)
                                dismiss()
                            },
                            onStartRename: {
                                editingID = preset.id
                                editName = preset.name
                            },
                            onConfirmRename: {
                                let trimmed = editName.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    presetStore.renamePreset(id: preset.id, newName: trimmed)
                                }
                                editingID = nil
                            },
                            onCancelRename: {
                                editingID = nil
                            },
                            onDuplicate: {
                                _ = presetStore.duplicatePreset(id: preset.id)
                            },
                            onDelete: {
                                presetStore.deletePreset(id: preset.id)
                            }
                        )
                    }
                }
            }
        }
        .frame(width: 420, height: 360)
    }
}

struct PresetRow: View {
    let preset: StylePreset
    let isEditing: Bool
    @Binding var editName: String
    let onApply: () -> Void
    let onStartRename: () -> Void
    let onConfirmRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if isEditing {
                TextField("이름", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onConfirmRename() }

                Button("확인") { onConfirmRename() }
                    .controlSize(.small)
                Button("취소") { onCancelRename() }
                    .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.body)
                    Text("JP: \(preset.subtitleStyle.japaneseFontFamily) \(Int(preset.subtitleStyle.japaneseFontSize))pt")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("적용") { onApply() }
                    .controlSize(.small)

                Menu {
                    Button("이름 변경") { onStartRename() }
                    Button("복제") { onDuplicate() }
                    Divider()
                    Button("삭제", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Ignore Regions Inspector

struct IgnoreRegionsInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("무시 구간")
                .font(.headline)

            Text("음성 인식에서 제외할 구간을 설정합니다.\n(MC 멘트, 관객 대화 등)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Add button
            Button {
                vm.addIgnoreRegionAtCurrentTime()
            } label: {
                Label("현재 위치에 무시 구간 추가", systemImage: "plus.circle")
            }
            .controlSize(.small)
            .disabled(!vm.project.hasVideo)

            if vm.project.ignoreRegions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("설정된 무시 구간이 없습니다")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(vm.project.ignoreRegions) { region in
                    IgnoreRegionRowView(region: region)
                }
            }
        }
    }
}

struct IgnoreRegionRowView: View {
    @EnvironmentObject var vm: ProjectViewModel
    let region: IgnoreRegion
    @State private var editingLabel: String = ""
    @State private var isEditingLabel: Bool = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Header with label and delete
                HStack {
                    if isEditingLabel {
                        TextField("라벨", text: $editingLabel, onCommit: {
                            vm.updateIgnoreRegion(id: region.id, label: editingLabel)
                            isEditingLabel = false
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    } else {
                        Text(region.label.isEmpty ? "무시 구간" : region.label)
                            .font(.caption.bold())
                            .onTapGesture {
                                editingLabel = region.label
                                isEditingLabel = true
                            }
                    }
                    Spacer()
                    Button {
                        vm.removeIgnoreRegion(id: region.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }

                // Start time
                HStack {
                    Text("시작")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(TimeFormatter.format(region.startTime))
                        .monospacedDigit()
                        .font(.caption)
                    Spacer()
                    Button("현재") {
                        vm.updateIgnoreRegion(id: region.id, startTime: vm.currentTime)
                    }
                    .controlSize(.mini)
                    HStack(spacing: 2) {
                        Button("-1s") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime - 1) }
                        Button("-0.1") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime - 0.1) }
                        Button("+0.1") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime + 0.1) }
                        Button("+1s") { vm.updateIgnoreRegion(id: region.id, startTime: region.startTime + 1) }
                    }
                    .controlSize(.mini)
                }

                // End time
                HStack {
                    Text("종료")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(TimeFormatter.format(region.endTime))
                        .monospacedDigit()
                        .font(.caption)
                    Spacer()
                    Button("현재") {
                        vm.updateIgnoreRegion(id: region.id, endTime: vm.currentTime)
                    }
                    .controlSize(.mini)
                    HStack(spacing: 2) {
                        Button("-1s") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime - 1) }
                        Button("-0.1") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime - 0.1) }
                        Button("+0.1") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime + 0.1) }
                        Button("+1s") { vm.updateIgnoreRegion(id: region.id, endTime: region.endTime + 1) }
                    }
                    .controlSize(.mini)
                }

                // Duration display
                HStack {
                    Text("길이: \(TimeFormatter.formatMMSS(region.duration))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("이 구간으로 이동") {
                        vm.seek(to: region.startTime)
                    }
                    .controlSize(.mini)
                }
            }
        }
    }
}
