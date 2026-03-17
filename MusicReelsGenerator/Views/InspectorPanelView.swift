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

    private func tabName(_ tab: InspectorTab) -> String {
        switch tab {
        case .block: return L10n.Tab.block(vm.lang)
        case .trim: return L10n.Tab.trim(vm.lang)
        case .crop: return L10n.Tab.crop(vm.lang)
        case .style: return L10n.Tab.style(vm.lang)
        case .overlay: return L10n.Tab.overlay(vm.lang)
        case .ignore: return L10n.Tab.ignore(vm.lang)
        case .info: return L10n.Tab.info(vm.lang)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tabName(tab)).tag(tab)
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
                Text(L10n.Block.title(vm.lang, index: idx + 1))
                    .font(.headline)

                GroupBox(L10n.Block.primaryLine(vm.lang)) {
                    Text(block.japanese)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                GroupBox(L10n.Block.secondaryLine(vm.lang)) {
                    Text(block.korean)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                GroupBox(L10n.Block.timing(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Block.start(vm.lang))
                                .frame(width: 40, alignment: .trailing)
                            if let start = block.startTime {
                                Text(TimeFormatter.format(start))
                                    .monospacedDigit()
                            } else {
                                Text(L10n.Block.notSet(vm.lang))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L10n.Block.setNow(vm.lang)) {
                                vm.setStartTimeToCurrent()
                            }
                            .controlSize(.small)
                        }

                        HStack {
                            Text(L10n.Block.end(vm.lang))
                                .frame(width: 40, alignment: .trailing)
                            if let end = block.endTime {
                                Text(TimeFormatter.format(end))
                                    .monospacedDigit()
                            } else {
                                Text(L10n.Block.notSet(vm.lang))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(L10n.Block.setNow(vm.lang)) {
                                vm.setEndTimeToCurrent()
                            }
                            .controlSize(.small)
                        }

                        if let confidence = block.confidence {
                            HStack {
                                Text(L10n.Block.confidence(vm.lang))
                                ConfidenceBadge(confidence: confidence, isManual: block.isManuallyAdjusted)
                            }
                        }
                    }
                }

                HStack {
                    Button(L10n.Block.seekToStart(vm.lang)) {
                        if let start = block.startTime {
                            vm.seek(to: start)
                        }
                    }
                    .disabled(block.startTime == nil)

                    Button(L10n.Block.seekToEnd(vm.lang)) {
                        if let end = block.endTime {
                            vm.seek(to: end)
                        }
                    }
                    .disabled(block.endTime == nil)
                }

                Divider()

                GroupBox(L10n.Block.correction(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(L10n.Block.setStartShiftFollowing(vm.lang)) {
                            vm.setStartTimeAndShiftFollowing()
                        }
                        .controlSize(.small)
                        .help(L10n.Block.setStartShiftHelp(vm.lang))

                        HStack(spacing: 4) {
                            Button("-0.5s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: -0.5) }
                            Button("-0.1s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: -0.1) }
                            Button("+0.1s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: 0.1) }
                            Button("+0.5s") { vm.shiftFollowingBlocks(fromBlockID: block.id, delta: 0.5) }
                        }
                        .controlSize(.mini)
                    }
                }

                GroupBox(L10n.Anchor.anchorCorrection(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Anchor controls
                        HStack {
                            if block.isUserAnchor {
                                Label(L10n.Anchor.userAnchor(vm.lang), systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                Spacer()
                                Button(L10n.Anchor.releaseAnchor(vm.lang)) {
                                    vm.unsetAnchor(id: block.id)
                                }
                                .controlSize(.small)
                            } else if block.isAnchor {
                                Label(L10n.Anchor.autoAnchor(vm.lang), systemImage: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(L10n.Anchor.promoteToUser(vm.lang)) {
                                    vm.setAnchor(id: block.id)
                                }
                                .controlSize(.small)
                                .help(L10n.Anchor.promoteHelp(vm.lang))
                            } else {
                                Button(L10n.Anchor.setAsAnchor(vm.lang)) {
                                    vm.setAnchor(id: block.id)
                                }
                                .controlSize(.small)
                                .help(L10n.Anchor.setAsAnchorHelp(vm.lang))
                            }
                        }

                        if block.isManuallyAdjusted && !block.isUserAnchor {
                            HStack(spacing: 4) {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                    .font(.caption2)
                                Text(L10n.Anchor.manuallyAdjustedHint(vm.lang))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        // Piecewise correction between anchors
                        Button(L10n.Anchor.correctBetween(vm.lang)) {
                            vm.correctBetweenSurroundingAnchors()
                        }
                        .controlSize(.small)
                        .disabled(!vm.hasSurroundingAnchors)
                        .help(L10n.Anchor.correctBetweenHelp(vm.lang))

                        Button(L10n.Anchor.correctAll(vm.lang)) {
                            vm.correctBetweenAllAnchors()
                        }
                        .controlSize(.small)
                        .disabled(vm.anchorCount < 2)
                        .help(L10n.Anchor.correctAllHelp(vm.lang))

                        Divider()

                        // Local re-alignment with legacy engine
                        Button(L10n.Anchor.localRealign(vm.lang)) {
                            Task { await vm.localRealignSurroundingRegion() }
                        }
                        .controlSize(.small)
                        .disabled(!vm.project.hasVideo || !vm.whisperAvailable || vm.isAligning)
                        .help(L10n.Anchor.localRealignHelp(vm.lang))
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.cursor")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text(L10n.Block.selectBlock(vm.lang))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Crop Inspector

struct CropInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    private var isHorizontal: Bool {
        vm.project.cropSettings.mode == .horizontal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Crop.settings(vm.lang))
                .font(.headline)

            // Mode picker
            GroupBox(L10n.Crop.mode(vm.lang)) {
                Picker("", selection: $vm.project.cropSettings.mode) {
                    ForEach(CropMode.allCases) { mode in
                        Text(L10n.CropModeName.displayName(mode, vm.lang)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vm.project.cropSettings.mode) { _, _ in
                    vm.isDirty = true
                }
            }

            // 세로모드: horizontal offset (가로모드에서는 항상 중앙)
            if !isHorizontal {
                GroupBox(L10n.Crop.horizontalPosition(vm.lang)) {
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

                        Button(L10n.Crop.centerH(vm.lang)) {
                            vm.project.cropSettings.horizontalOffset = 0
                            vm.isDirty = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            GroupBox(isHorizontal ? L10n.Crop.videoPosition(vm.lang) : L10n.Crop.verticalPosition(vm.lang)) {
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

                    Button(L10n.Crop.centerV(vm.lang)) {
                        vm.project.cropSettings.verticalOffset = 0
                        vm.isDirty = true
                    }
                    .controlSize(.small)
                }
            }

            GroupBox(L10n.Crop.zoom(vm.lang)) {
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
                        Button(L10n.Crop.resetZoom(vm.lang)) {
                            vm.project.cropSettings.zoomScale = 1.0
                            vm.isDirty = true
                        }
                        .controlSize(.small)
                    }
                }
            }

            // 가로모드: blur intensity
            if isHorizontal {
                GroupBox(L10n.Crop.blur(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Crop.blurWeak(vm.lang))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Slider(value: $vm.project.cropSettings.blurRadius, in: 10...50, step: 1)
                                .onChange(of: vm.project.cropSettings.blurRadius) { _, _ in
                                    vm.isDirty = true
                                }
                            Text(L10n.Crop.blurStrong(vm.lang))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Text(L10n.Crop.blurIntensity(vm.lang, value: Int(vm.project.cropSettings.blurRadius)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            GroupBox(L10n.Crop.output(vm.lang)) {
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
            Text(L10n.Style.subtitleStyle(vm.lang))
                .font(.headline)

            // Style Presets
            GroupBox(L10n.Style.presets(vm.lang)) {
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
                                Label(L10n.Style.applyPreset(vm.lang), systemImage: "paintbrush")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(L10n.Style.noPresets(vm.lang))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button(L10n.Style.saveCurrentStyle(vm.lang)) {
                            showSaveSheet = true
                        }
                        .controlSize(.small)

                        if !presetStore.presets.isEmpty {
                            Button(L10n.Style.manage(vm.lang)) {
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

            GroupBox(L10n.Style.primaryFont(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    FontFamilyPicker(
                        selection: $vm.project.subtitleStyle.japaneseFontFamily,
                        recommended: jaDefaults,
                        allFonts: allFonts
                    )

                    HStack {
                        Text(L10n.Style.size(vm.lang))
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

            GroupBox(L10n.Style.secondaryFont(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    FontFamilyPicker(
                        selection: $vm.project.subtitleStyle.koreanFontFamily,
                        recommended: koDefaults,
                        allFonts: allFonts
                    )

                    HStack {
                        Text(L10n.Style.size(vm.lang))
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

            GroupBox(L10n.Style.appearance(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.Style.outline(vm.lang))
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.outlineWidth, in: 0...8, step: 0.5)
                        Text("\(String(format: "%.1f", vm.project.subtitleStyle.outlineWidth))")
                            .monospacedDigit()
                            .frame(width: 28)
                    }

                    Toggle(L10n.Style.shadow(vm.lang), isOn: $vm.project.subtitleStyle.shadowEnabled)
                }
            }

            GroupBox(L10n.Style.position(vm.lang)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.Style.bottom(vm.lang))
                            .frame(width: 52, alignment: .trailing)
                        Slider(value: $vm.project.subtitleStyle.bottomMargin, in: 50...960, step: 5)
                        Text("\(Int(vm.project.subtitleStyle.bottomMargin))")
                            .monospacedDigit()
                            .frame(width: 32)
                    }

                    HStack {
                        Text(L10n.Style.gap(vm.lang))
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
    @EnvironmentObject var vm: ProjectViewModel
    @Binding var selection: String
    let recommended: [String]
    let allFonts: [String]

    var body: some View {
        Picker("Font", selection: $selection) {
            if !recommended.isEmpty {
                Section(L10n.Style.recommended(vm.lang)) {
                    ForEach(recommended, id: \.self) { font in
                        Text(font)
                            .font(.custom(font, size: 13))
                            .tag(font)
                    }
                }
                Divider()
            }

            Section(L10n.Style.allFonts(vm.lang)) {
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

// MARK: - Trim Inspector

struct TrimInspectorView: View {
    @EnvironmentObject var vm: ProjectViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Trim.settings(vm.lang))
                .font(.headline)

            if !vm.project.hasVideo {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(L10n.Trim.importVideoFirst(vm.lang))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Trim Start
                GroupBox(L10n.Trim.trimStart(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(TimeFormatter.format(vm.project.trimSettings.startTime))
                                .monospacedDigit()
                                .font(.title3)
                            Spacer()
                            Button(L10n.Trim.setToCurrent(vm.lang)) {
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
                GroupBox(L10n.Trim.trimEnd(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(TimeFormatter.format(vm.project.trimSettings.endTime))
                                .monospacedDigit()
                                .font(.title3)
                            Spacer()
                            Button(L10n.Trim.setToCurrent(vm.lang)) {
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
                GroupBox(L10n.Crop.output(vm.lang)) {
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(L10n.Trim.duration(vm.lang)) {
                            Text(TimeFormatter.formatMMSS(vm.trimmedDuration))
                                .monospacedDigit()
                        }
                        LabeledContent(L10n.Trim.range(vm.lang)) {
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
                Button(L10n.Trim.resetTrim(vm.lang)) {
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
            Text(L10n.Overlay.title(vm.lang))
                .font(.headline)

            Toggle(L10n.Overlay.enableOverlay(vm.lang), isOn: $vm.project.metadataOverlay.isEnabled)

            if vm.project.metadataOverlay.isEnabled {
                GroupBox(L10n.Overlay.titleLabel(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L10n.Overlay.songTitle(vm.lang), text: $vm.project.metadataOverlay.titleText)
                            .textFieldStyle(.roundedBorder)

                        Picker(L10n.Overlay.font(vm.lang), selection: $vm.project.metadataOverlay.titleFontFamily) {
                            ForEach(allFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Text(L10n.Style.size(vm.lang))
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

                GroupBox(L10n.Overlay.artist(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(L10n.Overlay.artistName(vm.lang), text: $vm.project.metadataOverlay.artistText)
                            .textFieldStyle(.roundedBorder)

                        Picker(L10n.Overlay.font(vm.lang), selection: $vm.project.metadataOverlay.artistFontFamily) {
                            ForEach(allFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Text(L10n.Style.size(vm.lang))
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

                GroupBox(L10n.Overlay.background(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Overlay.opacity(vm.lang))
                                .frame(width: 52, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.backgroundOpacity, in: 0...1, step: 0.05)
                            Text("\(Int(vm.project.metadataOverlay.backgroundOpacity * 100))%")
                                .monospacedDigit()
                                .frame(width: 36)
                        }

                        HStack {
                            Text(L10n.Overlay.radius(vm.lang))
                                .frame(width: 52, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.cornerRadius, in: 0...30, step: 1)
                            Text("\(Int(vm.project.metadataOverlay.cornerRadius))")
                                .monospacedDigit()
                                .frame(width: 28)
                        }
                    }
                }

                GroupBox(L10n.Style.position(vm.lang)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.Overlay.top(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.topMargin, in: 20...400, step: 5)
                            Text("\(Int(vm.project.metadataOverlay.topMargin))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }

                        HStack {
                            Text(L10n.Overlay.left(vm.lang))
                                .frame(width: 36, alignment: .trailing)
                            Slider(value: $vm.project.metadataOverlay.leftMargin, in: 20...300, step: 5)
                            Text("\(Int(vm.project.metadataOverlay.leftMargin))")
                                .monospacedDigit()
                                .frame(width: 32)
                        }
                    }
                }

                GroupBox(L10n.Overlay.padding(vm.lang)) {
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
                            Text(L10n.Style.gap(vm.lang))
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
    @EnvironmentObject var vm: ProjectViewModel
    let label: String
    @Binding var hexColor: String

    private static let presetHexes: [String] = [
        "#FFFFFF", "#E0FFFF", "#FFFACD", "#BDFCC9", "#FFB6C1",
    ]

    private func colorName(for hex: String) -> String {
        switch hex {
        case "#FFFFFF": return L10n.Style.colorWhite(vm.lang)
        case "#E0FFFF": return L10n.Style.colorCyan(vm.lang)
        case "#FFFACD": return L10n.Style.colorYellow(vm.lang)
        case "#BDFCC9": return L10n.Style.colorMint(vm.lang)
        case "#FFB6C1": return L10n.Style.colorPink(vm.lang)
        default: return hex
        }
    }

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

            ForEach(Self.presetHexes, id: \.self) { hex in
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
                .help(colorName(for: hex))
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
            Text(L10n.Preset.saveTitle(vm.lang))
                .font(.headline)

            TextField(L10n.Preset.presetName(vm.lang), text: $presetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { save() }

            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Text(L10n.Preset.saveNote(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(L10n.Common.cancel(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(L10n.Common.save(vm.lang)) { save() }
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
            errorText = L10n.Preset.enterName(vm.lang)
            return
        }
        if presetStore.nameExists(trimmed) {
            errorText = L10n.Preset.duplicateName(vm.lang)
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
                Text(L10n.Preset.manageTitle(vm.lang))
                    .font(.headline)
                Spacer()
                Button(L10n.Common.close(vm.lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if presetStore.presets.isEmpty {
                VStack(spacing: 8) {
                    Text(L10n.Preset.noPresetsStored(vm.lang))
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
    @EnvironmentObject var vm: ProjectViewModel
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
                TextField(L10n.Preset.name(vm.lang), text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onConfirmRename() }

                Button(L10n.Common.ok(vm.lang)) { onConfirmRename() }
                    .controlSize(.small)
                Button(L10n.Common.cancel(vm.lang)) { onCancelRename() }
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

                Button(L10n.Preset.apply(vm.lang)) { onApply() }
                    .controlSize(.small)

                Menu {
                    Button(L10n.Preset.rename(vm.lang)) { onStartRename() }
                    Button(L10n.Preset.duplicate(vm.lang)) { onDuplicate() }
                    Divider()
                    Button(L10n.Common.delete(vm.lang), role: .destructive) { onDelete() }
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
            Text(L10n.Ignore.title(vm.lang))
                .font(.headline)

            Text(L10n.Ignore.help(vm.lang))
                .font(.caption)
                .foregroundColor(.secondary)

            // Add button
            Button {
                vm.addIgnoreRegionAtCurrentTime()
            } label: {
                Label(L10n.Ignore.addAtCurrent(vm.lang), systemImage: "plus.circle")
            }
            .controlSize(.small)
            .disabled(!vm.project.hasVideo)

            if vm.project.ignoreRegions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.slash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(L10n.Ignore.noRegions(vm.lang))
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
                        TextField(L10n.Ignore.label(vm.lang), text: $editingLabel, onCommit: {
                            vm.updateIgnoreRegion(id: region.id, label: editingLabel)
                            isEditingLabel = false
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    } else {
                        Text(region.label.isEmpty ? L10n.Ignore.ignoreRegion(vm.lang) : region.label)
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
                    Text(L10n.Ignore.startLabel(vm.lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(TimeFormatter.format(region.startTime))
                        .monospacedDigit()
                        .font(.caption)
                    Spacer()
                    Button(L10n.Ignore.current(vm.lang)) {
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
                    Text(L10n.Ignore.endLabel(vm.lang))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30, alignment: .leading)
                    Text(TimeFormatter.format(region.endTime))
                        .monospacedDigit()
                        .font(.caption)
                    Spacer()
                    Button(L10n.Ignore.current(vm.lang)) {
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
                    Text(L10n.Ignore.length(vm.lang, time: TimeFormatter.formatMMSS(region.duration)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(L10n.Ignore.seekToRegion(vm.lang)) {
                        vm.seek(to: region.startTime)
                    }
                    .controlSize(.mini)
                }
            }
        }
    }
}
