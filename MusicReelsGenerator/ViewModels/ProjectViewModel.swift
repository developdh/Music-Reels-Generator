import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
class ProjectViewModel: ObservableObject {
    // MARK: - UI Language
    @Published var uiLanguage: UILanguage = {
        let raw = UserDefaults.standard.string(forKey: "uiLanguage") ?? "en"
        return UILanguage(rawValue: raw) ?? .en
    }() {
        didSet { UserDefaults.standard.set(uiLanguage.rawValue, forKey: "uiLanguage") }
    }

    /// Shorthand for current UI language
    var lang: UILanguage { uiLanguage }

    // MARK: - Project State
    @Published var project: Project = Project()
    @Published var projectFileURL: URL?
    @Published var isDirty: Bool = false

    // MARK: - Playback State
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    // MARK: - Selection State
    @Published var selectedBlockID: UUID?
    @Published var lyricsInputText: String = ""

    // MARK: - UI State
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var isProcessing: Bool = false
    @Published var processingMessage: String = ""

    // MARK: - Alignment State
    @Published var isAligning: Bool = false
    @Published var alignmentProgress: String = ""
    @Published var alignmentQualityMode: AlignmentQualityMode = .legacy

    // MARK: - Export State
    @Published var exportState: ExportState = .idle

    // MARK: - URL Import State
    @Published var showURLImportSheet: Bool = false
    @Published var youtubeDownloadState: YouTubeDownloadState = .idle

    // MARK: - Tool Availability
    @Published var ffmpegAvailable: Bool = false
    @Published var whisperAvailable: Bool = false
    @Published var vocalSeparationAvailable: Bool = false

    // MARK: - Waveform
    @Published var waveformPeaks: [Float] = []
    private var waveformTask: Task<Void, Never>?

    private var timeObserver: Any?
    private let exportService = ExportService()

    // MARK: - Undo / Redo

    let undoHistory = UndoHistory()
    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false

    private let snapshotEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let snapshotDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private var suspendUndoRecording = false

    var selectedBlock: LyricBlock? {
        guard let id = selectedBlockID else { return nil }
        return project.lyricBlocks.first { $0.id == id }
    }

    var selectedBlockIndex: Int? {
        guard let id = selectedBlockID else { return nil }
        return project.lyricBlocks.firstIndex { $0.id == id }
    }

    var currentBlock: LyricBlock? {
        project.lyricBlocks.first { block in
            guard let start = block.startTime, let end = block.endTime else { return false }
            return currentTime >= start && currentTime < end
        }
    }

    // MARK: - Initialization

    init() {
        checkToolAvailability()
        undoHistory.$canUndo.assign(to: &$canUndo)
        undoHistory.$canRedo.assign(to: &$canRedo)
    }

    // MARK: - Undo / Redo API

    /// Capture current project state before a mutation.
    /// `coalesceKey` groups rapid repeated edits (slider drags, keystrokes)
    /// into a single undo step.
    private func recordUndo(label: String, coalesceKey: String? = nil) {
        if suspendUndoRecording { return }
        guard let data = try? snapshotEncoder.encode(project) else { return }
        undoHistory.record(data, label: label, coalesceKey: coalesceKey)
    }

    func performUndo() {
        guard let current = try? snapshotEncoder.encode(project),
              let result = undoHistory.undo(current: current),
              let restored = try? snapshotDecoder.decode(Project.self, from: result.data) else { return }
        project = restored
        isDirty = true
        statusMessage = "Undo: \(result.label)"
    }

    func performRedo() {
        guard let current = try? snapshotEncoder.encode(project),
              let result = undoHistory.redo(current: current),
              let restored = try? snapshotDecoder.decode(Project.self, from: result.data) else { return }
        project = restored
        isDirty = true
        statusMessage = "Redo: \(result.label)"
    }

    func checkToolAvailability() {
        ffmpegAvailable = ProcessRunner.findFFmpeg() != nil
        whisperAvailable = ProcessRunner.findWhisper() != nil
        // Check advanced pipeline and demucs off the main thread — each probe
        // spawns Python (~0.5–1 s) and we don't want to block UI startup.
        Task.detached {
            let advanced = AdvancedAlignmentService.isAvailable
            let demucs = VocalSeparationService.isAvailable
            await MainActor.run { [weak self] in
                self?.advancedPipelineAvailable = advanced
                self?.vocalSeparationAvailable = demucs
            }
        }
    }

    /// Drop cached whisper segments. Call when an input that affects whisper
    /// transcription changes (e.g. vocal isolation toggled, language switched).
    func invalidateWhisperCache() {
        if !cachedWhisperSegments.isEmpty {
            print("[Alignment] Whisper cache invalidated")
        }
        cachedWhisperSegments = []
    }

    // MARK: - Video Import

    // MARK: - URL Download & Import

    func downloadFromURL(_ urlString: String) async {
        let provider = YouTubeDownloadRegistry.provider
        guard provider.isEnabled else {
            showError(L10n.Status.featureDisabled(lang))
            return
        }

        let downloadDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytdlp_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        do {
            let tempFileURL = try await provider.download(
                url: urlString,
                to: downloadDir
            ) { [weak self] state in
                Task { @MainActor in
                    self?.youtubeDownloadState = state
                }
            }

            // Move from temp to persistent storage (Application Support)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let videosDir = appSupport.appendingPathComponent("MusicReelsGenerator/Videos", isDirectory: true)
            try? FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

            let permanentURL = videosDir.appendingPathComponent(tempFileURL.lastPathComponent)
            // Remove existing file with same name if any
            try? FileManager.default.removeItem(at: permanentURL)
            try FileManager.default.moveItem(at: tempFileURL, to: permanentURL)
            // Clean up temp download directory
            try? FileManager.default.removeItem(at: downloadDir)

            showURLImportSheet = false
            youtubeDownloadState = .idle
            await importVideo(url: permanentURL)
        } catch {
            youtubeDownloadState = .failed(error.localizedDescription)
        }
    }

    func importVideo(url: URL) async {
        do {
            statusMessage = "Loading video..."
            let metadata = try await VideoService.extractMetadata(from: url)

            project.sourceVideoPath = url.path
            project.videoMetadata = metadata
            project.trimSettings = .fullDuration(metadata.duration)
            project.touch()
            isDirty = true
            // Undo across a video swap would leave broken state — reset.
            undoHistory.clear()

            setupPlayer(url: url)
            generateWaveform(from: url)
            statusMessage = "Video loaded: \(metadata.width)x\(metadata.height), \(TimeFormatter.formatMMSS(metadata.duration))"
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Generate the waveform peak array off the main actor. Failures are silent —
    /// the waveform is purely a visualization aid.
    func generateWaveform(from url: URL) {
        waveformTask?.cancel()
        waveformPeaks = []
        waveformTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let peaks = try await WaveformService.extractPeaks(from: url, bucketCount: 1500)
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    self?.waveformPeaks = peaks
                }
            } catch {
                print("[Waveform] generation failed: \(error.localizedDescription)")
            }
        }
    }

    func setupPlayer(url: URL) {
        player?.pause()
        if let observer = timeObserver, let p = player {
            p.removeTimeObserver(observer)
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        duration = project.videoMetadata.duration

        // Periodic time observer — also enforces trim end
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t = CMTimeGetSeconds(time)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = t
                self.handlePlaybackTimeAdvance(t)
            }
        }
    }

    /// During playback, jump from the end of one trim range to the start of the next
    /// (or pause if we ran past the last range). Inactive trim → no-op.
    private func handlePlaybackTimeAdvance(_ t: Double) {
        guard isPlaying else { return }
        let trim = project.trimSettings
        guard trim.isActive(sourceDuration: duration) else { return }
        let sorted = trim.sortedRanges
        // Find which range we're in (or just past).
        for (i, range) in sorted.enumerated() {
            // Slight tolerance so the boundary triggers reliably across the periodic observer cadence.
            if t >= range.endTime - 0.05 && t < range.endTime + 1.0 {
                if i + 1 < sorted.count {
                    seek(to: sorted[i + 1].startTime)
                } else {
                    player?.pause()
                    isPlaying = false
                    seek(to: range.endTime)
                }
                return
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Range-aware resume: if we're in a gap or past the last range, jump to the
            // first range that starts at or after currentTime. Falls back to source start.
            let sorted = project.trimSettings.sortedRanges
            if let containing = sorted.first(where: { $0.startTime <= currentTime && currentTime < $0.endTime - 0.15 }) {
                _ = containing  // already inside a kept range — just play
            } else if let next = sorted.first(where: { $0.startTime > currentTime - 0.05 }) {
                seek(to: next.startTime)
            } else if let first = sorted.first {
                // Past the last range — wrap to the first.
                seek(to: first.startTime)
            }
            player.play()
        }
        isPlaying = !isPlaying
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func stepForward(seconds: Double = 1.0) {
        seek(to: min(currentTime + seconds, duration))
    }

    func stepBackward(seconds: Double = 1.0) {
        seek(to: max(currentTime - seconds, 0))
    }

    func seekToBlock(_ block: LyricBlock) {
        if let start = block.startTime {
            seek(to: start)
        }
        selectedBlockID = block.id
    }

    // MARK: - Block Navigation

    func selectPreviousBlock() {
        guard !project.lyricBlocks.isEmpty else { return }
        if let idx = selectedBlockIndex {
            if idx > 0 {
                selectedBlockID = project.lyricBlocks[idx - 1].id
            }
        } else {
            selectedBlockID = project.lyricBlocks.last?.id
        }
    }

    func selectNextBlock() {
        guard !project.lyricBlocks.isEmpty else { return }
        if let idx = selectedBlockIndex {
            if idx < project.lyricBlocks.count - 1 {
                selectedBlockID = project.lyricBlocks[idx + 1].id
            }
        } else {
            selectedBlockID = project.lyricBlocks.first?.id
        }
    }

    // MARK: - Lyrics

    func parseLyrics() {
        do {
            let newBlocks = try LyricsParserService.parse(lyricsInputText)
            let oldBlocks = project.lyricBlocks
            recordUndo(label: "Parse Lyrics")

            // Preserve timing/anchor state for blocks whose text is unchanged.
            // Match by (primary, secondary) text, consuming each old block once
            // so duplicate lines pair left-to-right.
            var usedOldIndices = Set<Int>()
            let merged: [LyricBlock] = newBlocks.map { new in
                guard let matchIdx = oldBlocks.indices.first(where: {
                    !usedOldIndices.contains($0)
                        && oldBlocks[$0].japanese == new.japanese
                        && oldBlocks[$0].korean == new.korean
                }) else { return new }
                usedOldIndices.insert(matchIdx)
                let old = oldBlocks[matchIdx]
                var merged = new
                merged.startTime = old.startTime
                merged.endTime = old.endTime
                merged.confidence = old.confidence
                merged.manuallyAdjustedStart = old.manuallyAdjustedStart
                merged.manuallyAdjustedEnd = old.manuallyAdjustedEnd
                merged.isAnchor = old.isAnchor
                merged.isUserAnchor = old.isUserAnchor
                return merged
            }

            project.lyricBlocks = merged
            project.touch()
            isDirty = true
            let preserved = merged.filter { $0.hasTimingData }.count
            statusMessage = "Parsed \(merged.count) lyric blocks (\(preserved) with preserved timing)."
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Route a file dropped onto the window to the right import path based on extension.
    /// Single-file drops only — additional URLs in the same drop are ignored.
    func handleDroppedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case ProjectPersistenceService.fileExtension:
            if isDirty {
                let alert = NSAlert()
                alert.messageText = L10n.DragDrop.unsavedTitle(lang)
                alert.informativeText = L10n.DragDrop.unsavedMessage(lang)
                alert.addButton(withTitle: L10n.DragDrop.discardOpen(lang))
                alert.addButton(withTitle: L10n.Common.cancel(lang))
                if alert.runModal() != .alertFirstButtonReturn { return }
            }
            loadProject(from: url)

        case "mp4", "mov", "avi", "m4v", "mkv", "webm":
            Task { await importVideo(url: url) }

        case "lrc", "srt":
            importSubtitleFile(url: url)

        case "png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp":
            setWatermarkImage(from: url)

        default:
            showError(L10n.DragDrop.unsupported(lang, ext: ext))
        }
    }

    /// Load an image file as the project's watermark, re-encoding to PNG and
    /// embedding it inside the project. Reused by both the watermark inspector
    /// and the drag-and-drop handler.
    func setWatermarkImage(from url: URL) {
        let maxBytes = 5 * 1024 * 1024
        do {
            let raw = try Data(contentsOf: url)
            guard let img = NSImage(data: raw),
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                showError(L10n.Watermark.loadFailed(lang))
                return
            }
            if png.count > maxBytes {
                showError(L10n.Watermark.tooLarge(lang, mb: maxBytes / (1024 * 1024)))
                return
            }
            recordUndo(label: "Set Watermark")
            project.watermark.imageData = png
            project.watermark.enabled = true
            project.touch()
            isDirty = true
            statusMessage = L10n.Watermark.imageSetFromDrop(lang, name: url.lastPathComponent)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Replace current blocks with timed lyrics parsed from an LRC or SRT file.
    func importSubtitleFile(url: URL) {
        do {
            let imported = try SubtitleImportService.importFile(url: url)
            if !project.lyricBlocks.isEmpty {
                let alert = NSAlert()
                alert.messageText = L10n.SubtitleImport.replaceTitle(lang)
                alert.informativeText = L10n.SubtitleImport.replaceMessage(lang, count: imported.count)
                alert.addButton(withTitle: L10n.SubtitleImport.replaceConfirm(lang))
                alert.addButton(withTitle: L10n.Common.cancel(lang))
                if alert.runModal() != .alertFirstButtonReturn { return }
            }

            recordUndo(label: "Import Subtitles")
            project.lyricBlocks = imported
            project.touch()
            isDirty = true
            statusMessage = L10n.SubtitleImport.imported(lang, count: imported.count, name: url.lastPathComponent)
        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Rebuild `lyricsInputText` from current blocks so the bulk editor opens pre-filled.
    func syncLyricsInputTextFromBlocks() {
        lyricsInputText = project.lyricBlocks.map { block in
            block.korean.isEmpty ? block.japanese : "\(block.japanese)\n\(block.korean)"
        }.joined(separator: "\n\n")
    }

    /// Update a single block's text without touching timing or confidence.
    func updateBlockText(id: UUID, primary: String? = nil, secondary: String? = nil) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Edit Text", coalesceKey: "text-\(id.uuidString)")
        if let p = primary {
            project.lyricBlocks[idx].japanese = p
        }
        if let s = secondary {
            project.lyricBlocks[idx].korean = s
        }
        project.touch()
        isDirty = true
    }

    func updateBlock(id: UUID, startTime: Double? = nil, endTime: Double? = nil) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Adjust Timing", coalesceKey: "timing-\(id.uuidString)")

        if let st = startTime {
            project.lyricBlocks[idx].startTime = st
            project.lyricBlocks[idx].manuallyAdjustedStart = true
        }
        if let et = endTime {
            project.lyricBlocks[idx].endTime = et
            project.lyricBlocks[idx].manuallyAdjustedEnd = true
        }
        // Auto-anchor when both start and end are manually set
        if project.lyricBlocks[idx].manuallyAdjustedStart && project.lyricBlocks[idx].manuallyAdjustedEnd {
            project.lyricBlocks[idx].isAnchor = true
        }
        project.lyricBlocks[idx].confidence = 1.0
        project.touch()
        isDirty = true
    }

    func setStartTimeToCurrent() {
        guard let id = selectedBlockID else { return }
        updateBlock(id: id, startTime: currentTime)
    }

    func setEndTimeToCurrent() {
        guard let id = selectedBlockID else { return }
        updateBlock(id: id, endTime: currentTime)
    }

    /// Shift all blocks from the selected block onward by a delta
    func shiftFollowingBlocks(fromBlockID id: UUID, delta: Double) {
        guard let startIdx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Shift Timing", coalesceKey: "shift-\(id.uuidString)")

        for i in startIdx..<project.lyricBlocks.count {
            if let st = project.lyricBlocks[i].startTime {
                project.lyricBlocks[i].startTime = max(0, st + delta)
            }
            if let et = project.lyricBlocks[i].endTime {
                project.lyricBlocks[i].endTime = max(0, et + delta)
            }
        }
        project.touch()
        isDirty = true
    }

    /// Set start time of selected block and shift all following blocks by the same delta
    func setStartTimeAndShiftFollowing() {
        guard let id = selectedBlockID,
              let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }),
              let oldStart = project.lyricBlocks[idx].startTime else {
            // No old start — just set normally
            setStartTimeToCurrent()
            return
        }
        let delta = currentTime - oldStart
        shiftFollowingBlocks(fromBlockID: id, delta: delta)
        project.lyricBlocks[idx].manuallyAdjustedStart = true
        project.lyricBlocks[idx].isAnchor = true
        project.lyricBlocks[idx].confidence = 1.0
    }

    /// Toggle anchor status for a block
    func toggleAnchor(id: UUID) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Toggle Anchor")
        project.lyricBlocks[idx].isAnchor.toggle()
        project.touch()
        isDirty = true
    }

    // MARK: - Trim Controls

    func setTrimStart(to time: Double) {
        recordUndo(label: "Trim Start", coalesceKey: "trim-start")
        let clamped = max(0, min(time, project.trimSettings.endTime - 0.1))
        project.trimSettings.startTime = clamped
        project.touch()
        isDirty = true
    }

    func setTrimEnd(to time: Double) {
        recordUndo(label: "Trim End", coalesceKey: "trim-end")
        let clamped = max(project.trimSettings.startTime + 0.1, min(time, duration))
        project.trimSettings.endTime = clamped
        project.touch()
        isDirty = true
    }

    func setTrimStartToCurrent() {
        setTrimStart(to: currentTime)
    }

    func setTrimEndToCurrent() {
        setTrimEnd(to: currentTime)
    }

    func resetTrim() {
        recordUndo(label: "Reset Trim")
        project.trimSettings.reset(sourceDuration: duration)
        project.touch()
        isDirty = true
    }

    func nudgeTrimStart(by delta: Double) {
        setTrimStart(to: project.trimSettings.startTime + delta)
    }

    func nudgeTrimEnd(by delta: Double) {
        setTrimEnd(to: project.trimSettings.endTime + delta)
    }

    func setCrossfadeDuration(_ seconds: Double) {
        let clamped = max(0, min(seconds, 2.0))
        guard abs(project.trimSettings.crossfadeDuration - clamped) > 0.001 else { return }
        recordUndo(label: "Set Crossfade")
        project.trimSettings.crossfadeDuration = clamped
        project.touch()
        isDirty = true
    }

    // MARK: - Multi-Range Trim API

    /// Add a new trim range starting at the current playback time. The end time is set to
    /// either +5 s or the start of the next range, whichever comes first. Source-end
    /// is the upper bound. Newly created ranges are kept sorted by start time.
    func addTrimRange(at sourceTime: Double? = nil) {
        recordUndo(label: "Add Trim Range")
        let start = max(0, min(sourceTime ?? currentTime, duration))
        // Default end: 5s after start or next range's start, capped at source duration.
        let nextStart = project.trimSettings.sortedRanges.first(where: { $0.startTime > start })?.startTime ?? duration
        let end = min(start + 5.0, nextStart, duration)
        guard end > start + 0.05 else {
            showError(L10n.Trim.cannotAddRange(lang))
            return
        }
        project.trimSettings.ranges.append(TrimRange(startTime: start, endTime: end))
        project.trimSettings.ranges.sort { $0.startTime < $1.startTime }
        project.touch()
        isDirty = true
    }

    func removeTrimRange(id: UUID) {
        guard project.trimSettings.ranges.count > 1 else {
            // Don't allow removing the last range — leaves the project unable to export.
            return
        }
        recordUndo(label: "Remove Trim Range")
        project.trimSettings.ranges.removeAll { $0.id == id }
        project.touch()
        isDirty = true
    }

    func setRangeStart(id: UUID, to time: Double) {
        guard let idx = project.trimSettings.ranges.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Range Start", coalesceKey: "range-start-\(id.uuidString)")
        var ranges = project.trimSettings.ranges
        let upperBound = ranges[idx].endTime - 0.1
        let lowerBound = idx > 0 ? ranges[idx - 1].endTime : 0
        ranges[idx].startTime = max(lowerBound, min(time, upperBound))
        project.trimSettings.ranges = ranges
        project.touch()
        isDirty = true
    }

    func setRangeEnd(id: UUID, to time: Double) {
        guard let idx = project.trimSettings.ranges.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Range End", coalesceKey: "range-end-\(id.uuidString)")
        var ranges = project.trimSettings.ranges
        let lowerBound = ranges[idx].startTime + 0.1
        let upperBound = idx + 1 < ranges.count ? ranges[idx + 1].startTime : duration
        ranges[idx].endTime = max(lowerBound, min(time, upperBound))
        project.trimSettings.ranges = ranges
        project.touch()
        isDirty = true
    }

    func setRangeStartToCurrent(id: UUID) { setRangeStart(id: id, to: currentTime) }
    func setRangeEndToCurrent(id: UUID)   { setRangeEnd(id: id, to: currentTime) }

    func nudgeRangeStart(id: UUID, by delta: Double) {
        guard let r = project.trimSettings.ranges.first(where: { $0.id == id }) else { return }
        setRangeStart(id: id, to: r.startTime + delta)
    }

    func nudgeRangeEnd(id: UUID, by delta: Double) {
        guard let r = project.trimSettings.ranges.first(where: { $0.id == id }) else { return }
        setRangeEnd(id: id, to: r.endTime + delta)
    }

    /// Seek to the start of a specific trim range (used by inspector "play this range" buttons).
    func seekToRange(id: UUID) {
        guard let r = project.trimSettings.ranges.first(where: { $0.id == id }) else { return }
        seek(to: r.startTime)
    }

    /// Trimmed duration for display
    var trimmedDuration: Double {
        project.trimSettings.duration
    }

    /// Whether trim is actively cutting the video
    var isTrimActive: Bool {
        project.trimSettings.isActive(sourceDuration: duration)
    }

    // MARK: - Ignore Regions

    func addIgnoreRegion(startTime: Double, endTime: Double, label: String = "") {
        recordUndo(label: "Add Ignore Region")
        let region = IgnoreRegion(startTime: startTime, endTime: endTime, label: label)
        project.ignoreRegions.append(region)
        project.ignoreRegions.sort { $0.startTime < $1.startTime }
        project.touch()
        isDirty = true
        statusMessage = L10n.Status.ignoreRegionAdded(lang, from: TimeFormatter.formatMMSS(startTime), to: TimeFormatter.formatMMSS(endTime))
    }

    func removeIgnoreRegion(id: UUID) {
        recordUndo(label: "Remove Ignore Region")
        project.ignoreRegions.removeAll { $0.id == id }
        project.touch()
        isDirty = true
    }

    func updateIgnoreRegion(id: UUID, startTime: Double? = nil, endTime: Double? = nil, label: String? = nil) {
        guard let idx = project.ignoreRegions.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Edit Ignore Region", coalesceKey: "ignore-\(id.uuidString)")
        if let st = startTime {
            project.ignoreRegions[idx].startTime = max(0, min(st, project.ignoreRegions[idx].endTime - 0.1))
        }
        if let et = endTime {
            project.ignoreRegions[idx].endTime = max(project.ignoreRegions[idx].startTime + 0.1, min(et, duration))
        }
        if let l = label {
            project.ignoreRegions[idx].label = l
        }
        project.ignoreRegions.sort { $0.startTime < $1.startTime }
        project.touch()
        isDirty = true
    }

    func addIgnoreRegionAtCurrentTime() {
        let start = currentTime
        let end = min(currentTime + 10, duration)
        addIgnoreRegion(startTime: start, endTime: end)
    }

    // MARK: - Tool Availability (Advanced Pipeline)

    @Published var advancedPipelineAvailable: Bool = false

    // MARK: - Cached Alignment Data (transient, not persisted)

    /// Whisper segments cached after last alignment for fast local re-alignment
    private var cachedWhisperSegments: [WhisperSegment] = []

    // MARK: - Anchor Computed Properties

    /// Number of anchor blocks in the project
    var anchorCount: Int {
        project.lyricBlocks.filter { $0.isTrustedAnchor }.count
    }

    /// Whether the selected block has surrounding anchors for piecewise correction
    var hasSurroundingAnchors: Bool {
        guard let idx = selectedBlockIndex else { return false }
        let hasLeft = project.lyricBlocks[..<idx].contains { $0.isTrustedAnchor }
        let hasRight = project.lyricBlocks[(idx + 1)...].contains { $0.isTrustedAnchor }
        return hasLeft || hasRight
    }

    /// Find the anchor index range surrounding the selected block
    private func surroundingAnchorIndices(for blockIndex: Int) -> (left: Int?, right: Int?) {
        var left: Int? = nil
        for i in stride(from: blockIndex - 1, through: 0, by: -1) {
            if project.lyricBlocks[i].isTrustedAnchor {
                left = i
                break
            }
        }
        var right: Int? = nil
        for i in (blockIndex + 1)..<project.lyricBlocks.count {
            if project.lyricBlocks[i].isTrustedAnchor {
                right = i
                break
            }
        }
        return (left, right)
    }

    // MARK: - Anchor Operations

    func setAnchor(id: UUID) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Set Anchor")
        project.lyricBlocks[idx].isAnchor = true
        project.lyricBlocks[idx].isUserAnchor = true
        project.touch()
        isDirty = true
        statusMessage = L10n.Status.anchorSet(lang, index: idx + 1)
    }

    func unsetAnchor(id: UUID) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(label: "Release Anchor")
        project.lyricBlocks[idx].isAnchor = false
        project.lyricBlocks[idx].isUserAnchor = false
        project.touch()
        isDirty = true
        statusMessage = L10n.Status.anchorReleased(lang, index: idx + 1)
    }

    // MARK: - Piecewise Correction Between Anchors

    /// Correct timing for all non-anchored blocks between each pair of anchors.
    /// Distributes time proportionally by Japanese text length.
    func correctBetweenAllAnchors() {
        let blocks = project.lyricBlocks
        guard blocks.count >= 2 else { return }

        // Find all trusted anchor indices (user-set or both-start-end manually adjusted)
        let anchorIndices = blocks.indices.filter {
            blocks[$0].isTrustedAnchor
        }

        guard anchorIndices.count >= 2 else {
            showError(L10n.Status.needTwoAnchors(lang))
            return
        }

        recordUndo(label: "Correct Between Anchors")
        var totalCorrected = 0
        for pairIdx in 0..<(anchorIndices.count - 1) {
            let corrected = correctSegmentBetween(
                leftAnchorIdx: anchorIndices[pairIdx],
                rightAnchorIdx: anchorIndices[pairIdx + 1]
            )
            totalCorrected += corrected
        }

        project.touch()
        isDirty = true
        statusMessage = L10n.Status.allCorrectionDone(lang, anchors: anchorIndices.count, blocks: totalCorrected)
        print("[AnchorCorrection] Corrected \(totalCorrected) blocks across \(anchorIndices.count - 1) segments")
    }

    /// Correct timing only in the segment surrounding the selected block.
    func correctBetweenSurroundingAnchors() {
        guard let idx = selectedBlockIndex else { return }

        let (leftOpt, rightOpt) = surroundingAnchorIndices(for: idx)

        guard let left = leftOpt, let right = rightOpt else {
            showError(L10n.Status.needSurroundingAnchors(lang))
            return
        }

        recordUndo(label: "Correct Region")
        let corrected = correctSegmentBetween(leftAnchorIdx: left, rightAnchorIdx: right)
        project.touch()
        isDirty = true
        statusMessage = L10n.Status.regionCorrectionDone(lang, left: left + 1, right: right + 1, count: corrected)
    }

    /// Core piecewise correction: distribute time proportionally between two anchors.
    /// Returns the number of blocks corrected.
    @discardableResult
    private func correctSegmentBetween(leftAnchorIdx: Int, rightAnchorIdx: Int) -> Int {
        guard leftAnchorIdx < rightAnchorIdx - 1 else { return 0 }

        let leftEnd = project.lyricBlocks[leftAnchorIdx].endTime
            ?? project.lyricBlocks[leftAnchorIdx].startTime
            ?? 0
        let rightStart = project.lyricBlocks[rightAnchorIdx].startTime ?? duration

        let availableTime = rightStart - leftEnd
        guard availableTime > 0.1 else { return 0 }

        // Collect non-trusted-anchor middle blocks
        var middleIndices: [Int] = []
        for idx in (leftAnchorIdx + 1)..<rightAnchorIdx {
            if !project.lyricBlocks[idx].isTrustedAnchor {
                middleIndices.append(idx)
            }
        }

        guard !middleIndices.isEmpty else { return 0 }

        // Use vocal-range-aware distribution if whisper segments are available
        if !cachedWhisperSegments.isEmpty {
            // Reindex middle blocks into a contiguous temp array, distribute, then write back
            let filteredSegments = WhisperAlignmentService.filterIgnoredSegments(cachedWhisperSegments, ignoreRegions: project.ignoreRegions)
            var tempBlocks = middleIndices.map { project.lyricBlocks[$0] }
            WhisperAlignmentService.distributeBlocksIntoVocalRanges(
                blocks: &tempBlocks,
                indices: 0..<tempBlocks.count,
                segments: filteredSegments,
                startBound: leftEnd,
                endBound: rightStart,
                confidence: 0.3
            )
            for (j, idx) in middleIndices.enumerated() {
                project.lyricBlocks[idx].startTime = tempBlocks[j].startTime
                project.lyricBlocks[idx].endTime = tempBlocks[j].endTime
                project.lyricBlocks[idx].confidence = max(project.lyricBlocks[idx].confidence ?? 0, 0.3)
            }
        } else {
            // Fallback: gap-aware proportional distribution (no segment data)
            // Estimate duration per block based on text length, leave gaps
            let weights = middleIndices.map { max(1.0, Double(project.lyricBlocks[$0].japanese.count)) }
            let totalWeight = weights.reduce(0, +)
            let estimatedTotal = middleIndices.reduce(0.0) { sum, idx in
                let chars = max(1, project.lyricBlocks[idx].japanese.count)
                return sum + min(max(Double(chars) / 4.0, 1.5), 8.0)
            }

            if estimatedTotal < availableTime * 0.85 {
                // Blocks need less time than available — space them out with gaps
                let spacing = (availableTime - estimatedTotal) / Double(middleIndices.count + 1)
                var cursor = leftEnd + spacing
                for idx in middleIndices {
                    let chars = max(1, project.lyricBlocks[idx].japanese.count)
                    let dur = min(max(Double(chars) / 4.0, 1.5), 8.0)
                    project.lyricBlocks[idx].startTime = cursor
                    project.lyricBlocks[idx].endTime = cursor + dur
                    project.lyricBlocks[idx].confidence = max(project.lyricBlocks[idx].confidence ?? 0, 0.3)
                    cursor += dur + spacing
                }
            } else {
                // Blocks need most of the time — proportional with small gaps
                let gapPerBlock = min(0.3, availableTime * 0.02)
                let totalGaps = gapPerBlock * Double(max(0, middleIndices.count - 1))
                let usable = availableTime - totalGaps

                var cursor = leftEnd
                for (j, idx) in middleIndices.enumerated() {
                    let proportion = weights[j] / totalWeight
                    let blockDuration = usable * proportion
                    project.lyricBlocks[idx].startTime = cursor
                    project.lyricBlocks[idx].endTime = cursor + blockDuration
                    project.lyricBlocks[idx].confidence = max(project.lyricBlocks[idx].confidence ?? 0, 0.3)
                    cursor += blockDuration + gapPerBlock
                }
            }
        }

        print("[AnchorCorrection] Corrected \(middleIndices.count) blocks between anchors #\(leftAnchorIdx + 1) and #\(rightAnchorIdx + 1) (\(String(format: "%.1f", leftEnd))–\(String(format: "%.1f", rightStart))s)")
        return middleIndices.count
    }

    // MARK: - Local Re-Alignment (Legacy Engine)

    /// Re-align only the region surrounding the selected block using the legacy engine.
    /// Uses cached whisper segments if available, otherwise transcribes first.
    func localRealignSurroundingRegion() async {
        guard let idx = selectedBlockIndex else { return }

        let (leftOpt, rightOpt) = surroundingAnchorIndices(for: idx)
        let fromIndex = (leftOpt ?? 0) + (leftOpt != nil ? 1 : 0)
        let toIndex = (rightOpt ?? project.lyricBlocks.count - 1) - (rightOpt != nil ? 1 : 0)

        guard fromIndex <= toIndex else { return }

        await localRealignRange(fromIndex: fromIndex, toIndex: toIndex)
    }

    /// Re-align a specific range of blocks using the legacy whisper engine.
    /// Anchored and manually adjusted blocks within the range are preserved.
    func localRealignRange(fromIndex: Int, toIndex: Int) async {
        guard fromIndex >= 0, toIndex < project.lyricBlocks.count, fromIndex <= toIndex else { return }
        guard project.hasVideo else {
            showError(L10n.Status.importVideoFirst(lang))
            return
        }
        guard ffmpegAvailable, whisperAvailable else {
            showError(L10n.Status.needTools(lang))
            return
        }

        recordUndo(label: "Local Realign")
        isAligning = true
        alignmentProgress = L10n.Status.preparingRealign(lang)

        defer {
            isAligning = false
            alignmentProgress = ""
        }

        do {
            // Ensure we have whisper segments (cached or freshly transcribed)
            if cachedWhisperSegments.isEmpty {
                alignmentProgress = L10n.Status.extractingAudio(lang)
                let tempDir = NSTemporaryDirectory()
                let audioURL = URL(fileURLWithPath: tempDir + "audio_\(project.id.uuidString).wav")

                try await prepareWhisperAudio(
                    videoURL: project.sourceVideoURL!,
                    audioURL: audioURL,
                    stageLabel: "Audio"
                )

                alignmentProgress = L10n.Status.recognizingSpeech(lang)
                cachedWhisperSegments = try await WhisperAlignmentService.transcribe(
                    audioURL: audioURL,
                    language: project.primaryLanguage.whisperLanguageFlag
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = msg
                    }
                }
                print("[LocalRealign] Transcribed \(cachedWhisperSegments.count) segments (cached for future use)")
            }

            // Determine time bounds from surrounding context
            let timeBefore: Double
            if fromIndex > 0, let end = project.lyricBlocks[fromIndex - 1].endTime {
                timeBefore = end
            } else if fromIndex > 0, let start = project.lyricBlocks[fromIndex - 1].startTime {
                timeBefore = start
            } else {
                timeBefore = 0
            }

            let timeAfter: Double
            if toIndex < project.lyricBlocks.count - 1, let start = project.lyricBlocks[toIndex + 1].startTime {
                timeAfter = start
            } else {
                timeAfter = duration
            }

            alignmentProgress = L10n.Status.realigning(lang, from: fromIndex + 1, to: toIndex + 1)

            // Run bounded local re-alignment via legacy engine
            let updated = WhisperAlignmentService.realignRegion(
                segments: cachedWhisperSegments,
                allBlocks: project.lyricBlocks,
                fromIndex: fromIndex,
                toIndex: toIndex,
                timeBefore: timeBefore,
                timeAfter: timeAfter,
                mode: .legacy,
                ignoreRegions: project.ignoreRegions
            )

            // Apply results — the realignRegion method already preserves anchors
            project.lyricBlocks = updated
            project.touch()
            isDirty = true

            statusMessage = L10n.Status.realignComplete(lang, from: fromIndex + 1, to: toIndex + 1)

        } catch {
            showError(error.localizedDescription)
        }
    }

    /// Produce a 16 kHz mono WAV ready for whisper.cpp, optionally running
    /// vocal isolation (demucs) first. On vocal-isolation failure or when
    /// demucs is unavailable, falls back to the plain extraction so alignment
    /// still proceeds — vocal isolation is an accuracy boost, not a hard
    /// dependency.
    private func prepareWhisperAudio(
        videoURL: URL,
        audioURL: URL,
        stageLabel: String
    ) async throws {
        let shouldIsolate = project.useVocalIsolation && vocalSeparationAvailable
        if shouldIsolate {
            do {
                try await VocalSeparationService.prepareVocalAudio(
                    fromVideo: videoURL,
                    outputURL: audioURL
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = "\(stageLabel): \(msg)"
                    }
                }
                return
            } catch {
                print("[VocalSep] Failed, falling back to raw audio: \(error.localizedDescription)")
                statusMessage = "Vocal separation failed, using raw audio: \(error.localizedDescription)"
                // fall through to plain extraction
            }
        }

        try await AudioExtractionService.extractAudio(
            from: videoURL,
            to: audioURL
        ) { [weak self] msg in
            Task { @MainActor in
                self?.alignmentProgress = "\(stageLabel): \(msg)"
            }
        }
    }

    // MARK: - Auto Alignment

    func runAutoAlignment() async {
        guard project.hasVideo else {
            showError("Import a video first.")
            return
        }
        guard project.hasLyrics else {
            showError("Add lyrics first.")
            return
        }
        guard ffmpegAvailable else {
            showError("FFmpeg not found. Install with: brew install ffmpeg")
            return
        }

        // Legacy mode uses whisper-cpp, all others use Python pipeline.
        let useAdvanced = alignmentQualityMode.usesAdvancedPipeline && advancedPipelineAvailable
        if alignmentQualityMode.usesLegacyPipeline && !whisperAvailable {
            showError("whisper.cpp not found. Install with: brew install whisper-cpp")
            return
        }
        if alignmentQualityMode.usesAdvancedPipeline && !advancedPipelineAvailable {
            showError("Python pipeline not available. Run: cd Scripts && ./setup_alignment.sh")
            return
        }

        recordUndo(label: "Auto-Align")
        isAligning = true
        alignmentProgress = "Starting alignment..."
        let pipelineStart = CFAbsoluteTimeGetCurrent()

        // Save user-set anchors before alignment (alignment service overwrites isAnchor but not isUserAnchor)
        let userAnchorIDs = Set(project.lyricBlocks.filter { $0.isUserAnchor }.map { $0.id })

        // Use defer to guarantee state cleanup, even on unexpected errors
        defer {
            isAligning = false
            alignmentProgress = ""
        }

        do {
            // Stage 1: Extract (and optionally vocal-isolate) audio
            var stageStart = CFAbsoluteTimeGetCurrent()
            let stage1Label = (project.useVocalIsolation && vocalSeparationAvailable)
                ? "Stage 1: Preparing isolated vocals..."
                : "Stage 1: Extracting audio..."
            alignmentProgress = stage1Label
            print("[Alignment] Stage 1: \(project.useVocalIsolation && vocalSeparationAvailable ? "Vocal-isolated audio prep" : "Audio extraction") starting")

            let tempDir = NSTemporaryDirectory()
            let audioURL = URL(fileURLWithPath: tempDir + "audio_\(project.id.uuidString).wav")

            try await prepareWhisperAudio(
                videoURL: project.sourceVideoURL!,
                audioURL: audioURL,
                stageLabel: "Stage 1"
            )

            var elapsed = CFAbsoluteTimeGetCurrent() - stageStart
            print("[Alignment] Stage 1: Audio prep completed in \(String(format: "%.1f", elapsed))s")

            let aligned: [LyricBlock]

            if useAdvanced {
                // Stage 2: Advanced pipeline
                stageStart = CFAbsoluteTimeGetCurrent()
                alignmentProgress = "Stage 2: Running advanced alignment pipeline..."
                print("[Alignment] Stage 2: Advanced pipeline starting (\(alignmentQualityMode.rawValue) mode)")

                aligned = try await AdvancedAlignmentService.align(
                    audioURL: audioURL,
                    lyrics: project.lyricBlocks,
                    mode: alignmentQualityMode
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = "Stage 2: \(msg)"
                    }
                }

                elapsed = CFAbsoluteTimeGetCurrent() - stageStart
                print("[Alignment] Stage 2: Advanced pipeline completed in \(String(format: "%.1f", elapsed))s")
            } else {
                // Stage 2a: Whisper transcription
                stageStart = CFAbsoluteTimeGetCurrent()
                alignmentProgress = "Stage 2: Running whisper transcription..."
                print("[Alignment] Stage 2: Whisper transcription starting")

                if !whisperAvailable {
                    showError("whisper.cpp not found and advanced pipeline not available. "
                              + "Install whisper-cpp with: brew install whisper-cpp, "
                              + "or set up the advanced pipeline: cd Scripts && ./setup_alignment.sh")
                    return
                }
                let segments = try await WhisperAlignmentService.transcribe(
                    audioURL: audioURL,
                    language: project.primaryLanguage.whisperLanguageFlag
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = "Stage 2: \(msg)"
                    }
                }

                // Cache segments for fast local re-alignment later
                self.cachedWhisperSegments = segments

                // Dump whisper segments for debugging
                var segLines: [String] = ["=== WHISPER SEGMENTS ==="]
                for (i, seg) in segments.enumerated() {
                    segLines.append(String(format: "[%2d] %6.2f–%6.2f (dur=%.2f) %@", i, seg.startTime, seg.endTime, seg.endTime - seg.startTime, String(seg.text.prefix(40))))
                }
                segLines.append("=== END ===")
                try? segLines.joined(separator: "\n").write(toFile: "/tmp/mreels_whisper_segments.txt", atomically: true, encoding: .utf8)

                elapsed = CFAbsoluteTimeGetCurrent() - stageStart
                print("[Alignment] Stage 2: Whisper transcription completed in \(String(format: "%.1f", elapsed))s (\(segments.count) segments, cached)")

                // Stage 3: Alignment matching
                stageStart = CFAbsoluteTimeGetCurrent()
                alignmentProgress = "Stage 3: Matching lyrics..."
                print("[Alignment] Stage 3: Lyric matching starting")

                aligned = WhisperAlignmentService.align(
                    segments: segments,
                    to: project.lyricBlocks,
                    mode: alignmentQualityMode,
                    ignoreRegions: project.ignoreRegions
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = "Stage 3: \(msg)"
                    }
                }

                elapsed = CFAbsoluteTimeGetCurrent() - stageStart
                print("[Alignment] Stage 3: Lyric matching completed in \(String(format: "%.1f", elapsed))s")
            }

            project.lyricBlocks = aligned

            // Restore isUserAnchor flags — alignment service doesn't know about them
            for i in project.lyricBlocks.indices {
                project.lyricBlocks[i].isUserAnchor = userAnchorIDs.contains(project.lyricBlocks[i].id)
            }

            project.touch()
            isDirty = true

            let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
            let matched = aligned.filter { ($0.confidence ?? 0) > 0.5 }.count
            statusMessage = "Alignment complete: \(matched)/\(aligned.count) blocks matched (\(String(format: "%.1f", totalElapsed))s)"
            print("[Alignment] Pipeline complete in \(String(format: "%.1f", totalElapsed))s — \(matched)/\(aligned.count) blocks matched")

            // Auto-correct between anchors if at least 2 anchors exist.
            // Bundle into the parent "Auto-Align" undo step — a single Cmd+Z reverts the whole pipeline.
            if anchorCount >= 2 {
                suspendUndoRecording = true
                correctBetweenAllAnchors()
                suspendUndoRecording = false
                print("[Alignment] Auto-corrected between \(anchorCount) anchors after alignment")
            }

            // Dump final timing to file for debugging
            dumpBlockTimingToFile(label: "post-alignment")

            // Cleanup
            try? FileManager.default.removeItem(at: audioURL)

        } catch {
            let totalElapsed = CFAbsoluteTimeGetCurrent() - pipelineStart
            print("[Alignment] Pipeline FAILED after \(String(format: "%.1f", totalElapsed))s: \(error.localizedDescription)")
            showError(error.localizedDescription)
        }
    }

    /// Dump current block timing to /tmp for debugging gap issues
    private func dumpBlockTimingToFile(label: String) {
        var lines: [String] = ["=== BLOCK TIMING DUMP (\(label)) ==="]
        for (i, block) in project.lyricBlocks.enumerated() {
            let timeStr: String
            if let s = block.startTime, let e = block.endTime {
                timeStr = String(format: "%6.2f–%6.2f (dur=%.2f)", s, e, e - s)
            } else {
                timeStr = "   -.--–   -.-- (no timing)"
            }
            if i > 0, let prevEnd = project.lyricBlocks[i - 1].endTime, let curStart = block.startTime {
                let gap = curStart - prevEnd
                if gap > 0.5 {
                    lines.append(String(format: "     ⏸ GAP %.2fs", gap))
                }
            }
            let ja = String(block.japanese.prefix(25))
            let conf = block.confidence ?? 0
            lines.append(String(format: "[%2d] conf=%.2f %@ %@", i, conf, timeStr, ja))
        }
        lines.append("=== END DUMP ===")
        try? lines.joined(separator: "\n").write(toFile: "/tmp/mreels_timing_\(label).txt", atomically: true, encoding: .utf8)
    }

    // MARK: - Export

    func exportVideo(to outputURL: URL) async {
        do {
            try await exportService.export(project: project, outputURL: outputURL) { [weak self] state in
                Task { @MainActor in
                    self?.exportState = state
                }
            }
            statusMessage = "Export complete!"
        } catch {
            exportState = .failed(error.localizedDescription)
            showError(error.localizedDescription)
        }
    }

    func exportSRT(to outputURL: URL) {
        do {
            try SubtitleExportService.exportSRT(project: project, to: outputURL)
            statusMessage = "SRT exported: \(outputURL.lastPathComponent)"
        } catch {
            showError(error.localizedDescription)
        }
    }

    func exportLRC(to outputURL: URL) {
        do {
            try SubtitleExportService.exportLRC(project: project, to: outputURL)
            statusMessage = "LRC exported: \(outputURL.lastPathComponent)"
        } catch {
            showError(error.localizedDescription)
        }
    }

    // MARK: - Persistence

    /// Returns true if already has a file URL (saved in-place), false if caller should show Save As panel
    @discardableResult
    func saveProject() -> Bool {
        guard let url = projectFileURL else {
            // No file URL yet — caller should present Save As dialog
            return false
        }
        do {
            try ProjectPersistenceService.save(project, to: url)
            isDirty = false
            statusMessage = "Project saved."
            return true
        } catch {
            showError(error.localizedDescription)
            return false
        }
    }

    func saveProjectAs(to url: URL) {
        do {
            try ProjectPersistenceService.save(project, to: url)
            projectFileURL = url
            isDirty = false
            statusMessage = "Project saved to \(url.lastPathComponent)"
        } catch {
            showError(error.localizedDescription)
        }
    }

    func loadProject(from url: URL) {
        do {
            project = try ProjectPersistenceService.load(from: url)
            projectFileURL = url
            isDirty = false
            undoHistory.clear()

            if let videoURL = project.sourceVideoURL,
               FileManager.default.fileExists(atPath: videoURL.path) {
                setupPlayer(url: videoURL)
                generateWaveform(from: videoURL)
            }

            statusMessage = "Project loaded: \(project.title)"
            dumpBlockTimingToFile(label: "loaded-project")
        } catch {
            showError(error.localizedDescription)
        }
    }

    func newProject() {
        player?.pause()
        project = Project()
        projectFileURL = nil
        isDirty = false
        selectedBlockID = nil
        lyricsInputText = ""
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        cachedWhisperSegments = []
        waveformTask?.cancel()
        waveformPeaks = []
        undoHistory.clear()
        statusMessage = "New project created."
    }

    // MARK: - Style Presets

    /// Apply a style preset to the current project.
    /// Copies subtitle and overlay style values; preserves title/artist text content.
    func applyPreset(_ preset: StylePreset) {
        recordUndo(label: "Apply Preset")
        project.subtitleStyle = preset.subtitleStyle
        preset.overlayStyle.apply(to: &project.metadataOverlay)
        project.touch()
        isDirty = true
        statusMessage = L10n.Status.presetApplied(lang, name: preset.name)
    }

    /// Save the current project style as a new named preset.
    @discardableResult
    func saveCurrentStyleAsPreset(name: String) -> StylePreset {
        let preset = StylePresetStore.shared.savePreset(
            name: name,
            subtitleStyle: project.subtitleStyle,
            metadataOverlay: project.metadataOverlay
        )
        statusMessage = L10n.Status.presetSaved(lang, name: name)
        return preset
    }

    // MARK: - Project Templates

    /// Apply a template to the current project. Always overrides style, overlay style,
    /// language, and alignment mode. Crop mode + blur are only overridden when no video
    /// has been imported yet (otherwise the user has likely tuned them for this video).
    func applyTemplate(_ template: ProjectTemplate) {
        recordUndo(label: "Apply Template")

        project.subtitleStyle = template.subtitleStyle
        template.overlayStyle.apply(to: &project.metadataOverlay)
        project.primaryLanguage = template.primaryLanguage
        alignmentQualityMode = template.alignmentQualityMode

        if !project.hasVideo {
            project.cropSettings.mode = template.cropMode
            project.cropSettings.blurRadius = template.horizontalBlurRadius
        }
        // Output canvas (aspect + resolution) is always applied — it's part of the
        // template's visual identity, independent of the source video.
        project.cropSettings.outputAspectRatio = template.outputAspectRatio
        project.cropSettings.outputResolution = template.outputResolution
        let maxMargin = Double(project.cropSettings.outputHeight) / 2.0
        if project.subtitleStyle.bottomMargin > maxMargin {
            project.subtitleStyle.bottomMargin = max(50, maxMargin)
        }

        project.touch()
        isDirty = true
        statusMessage = L10n.Status.templateApplied(lang, name: template.name)
    }

    /// Create a fresh project pre-populated from a template.
    func newProject(fromTemplate template: ProjectTemplate) {
        newProject()
        // newProject resets to defaults — apply on top.
        // Skip the undo entry since the project is brand new.
        suspendUndoRecording = true
        applyTemplate(template)
        suspendUndoRecording = false
        undoHistory.clear()
        statusMessage = L10n.Status.templateApplied(lang, name: template.name)
    }

    /// Save the current project's style/language/layout as a reusable template.
    @discardableResult
    func saveCurrentAsTemplate(name: String) -> ProjectTemplate {
        let template = ProjectTemplateStore.shared.saveTemplate(
            name: name,
            project: project,
            alignmentQualityMode: alignmentQualityMode
        )
        statusMessage = L10n.Status.templateSaved(lang, name: name)
        return template
    }

    // MARK: - Helpers

    func showError(_ message: String) {
        errorMessage = message
        showError = true
        statusMessage = "Error: \(message)"
    }
}
