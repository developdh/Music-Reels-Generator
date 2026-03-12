import Foundation
import AVFoundation
import Combine
import SwiftUI

@MainActor
class ProjectViewModel: ObservableObject {
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
    @Published var alignmentQualityMode: AlignmentQualityMode = .balanced

    // MARK: - Export State
    @Published var exportState: ExportState = .idle

    // MARK: - Tool Availability
    @Published var ffmpegAvailable: Bool = false
    @Published var whisperAvailable: Bool = false

    private var timeObserver: Any?
    private let exportService = ExportService()

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
    }

    func checkToolAvailability() {
        ffmpegAvailable = ProcessRunner.findFFmpeg() != nil
        whisperAvailable = ProcessRunner.findWhisper() != nil
        checkAdvancedPipelineAvailability()
    }

    // MARK: - Video Import

    func importVideo(url: URL) async {
        do {
            statusMessage = "Loading video..."
            let metadata = try await VideoService.extractMetadata(from: url)

            project.sourceVideoPath = url.path
            project.videoMetadata = metadata
            project.trimSettings = .fullDuration(metadata.duration)
            project.touch()
            isDirty = true

            setupPlayer(url: url)
            statusMessage = "Video loaded: \(metadata.width)x\(metadata.height), \(TimeFormatter.formatMMSS(metadata.duration))"
        } catch {
            showError(error.localizedDescription)
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
                // Stop at trim end
                let trimEnd = self.project.trimSettings.endTime
                if trimEnd > 0 && t >= trimEnd && self.isPlaying {
                    self.player?.pause()
                    self.isPlaying = false
                    self.seek(to: trimEnd)
                }
            }
        }
    }

    // MARK: - Playback Controls

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            // Jump to trim start if before it
            let trimStart = project.trimSettings.startTime
            let trimEnd = project.trimSettings.endTime
            if currentTime < trimStart {
                seek(to: trimStart)
            } else if trimEnd > 0 && currentTime >= trimEnd {
                seek(to: trimStart)
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

    // MARK: - Lyrics

    func parseLyrics() {
        do {
            let blocks = try LyricsParserService.parse(lyricsInputText)
            project.lyricBlocks = blocks
            project.touch()
            isDirty = true
            statusMessage = "Parsed \(blocks.count) lyric blocks."
        } catch {
            showError(error.localizedDescription)
        }
    }

    func updateBlock(id: UUID, startTime: Double? = nil, endTime: Double? = nil) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }

        if let st = startTime {
            project.lyricBlocks[idx].startTime = st
        }
        if let et = endTime {
            project.lyricBlocks[idx].endTime = et
        }
        project.lyricBlocks[idx].isManuallyAdjusted = true
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
        project.lyricBlocks[idx].isManuallyAdjusted = true
        project.lyricBlocks[idx].isAnchor = true
        project.lyricBlocks[idx].confidence = 1.0
    }

    /// Toggle anchor status for a block
    func toggleAnchor(id: UUID) {
        guard let idx = project.lyricBlocks.firstIndex(where: { $0.id == id }) else { return }
        project.lyricBlocks[idx].isAnchor.toggle()
        project.touch()
        isDirty = true
    }

    // MARK: - Trim Controls

    func setTrimStart(to time: Double) {
        let clamped = max(0, min(time, project.trimSettings.endTime - 0.1))
        project.trimSettings.startTime = clamped
        project.touch()
        isDirty = true
    }

    func setTrimEnd(to time: Double) {
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

    /// Trimmed duration for display
    var trimmedDuration: Double {
        project.trimSettings.duration
    }

    /// Whether trim is actively cutting the video
    var isTrimActive: Bool {
        project.trimSettings.isActive(sourceDuration: duration)
    }

    // MARK: - Tool Availability (Advanced Pipeline)

    @Published var advancedPipelineAvailable: Bool = false

    func checkAdvancedPipelineAvailability() {
        advancedPipelineAvailable = AdvancedAlignmentService.isAvailable
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

        // For Fast mode, require whisper-cpp. For advanced modes, require Python pipeline.
        let useAdvanced = alignmentQualityMode.usesAdvancedPipeline && advancedPipelineAvailable
        if !useAdvanced && !whisperAvailable {
            showError("whisper.cpp not found. Install with: brew install whisper-cpp")
            return
        }

        isAligning = true
        alignmentProgress = "Starting alignment..."

        do {
            // Step 1: Extract audio (needed by both pipelines)
            let tempDir = NSTemporaryDirectory()
            let audioURL = URL(fileURLWithPath: tempDir + "audio_\(project.id.uuidString).wav")

            try await AudioExtractionService.extractAudio(
                from: project.sourceVideoURL!,
                to: audioURL
            ) { [weak self] msg in
                Task { @MainActor in
                    self?.alignmentProgress = msg
                }
            }

            let aligned: [LyricBlock]

            if useAdvanced {
                // Advanced pipeline: Python-based forced alignment
                alignmentProgress = "Running advanced alignment pipeline..."
                aligned = try await AdvancedAlignmentService.align(
                    audioURL: audioURL,
                    lyrics: project.lyricBlocks,
                    mode: alignmentQualityMode
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = msg
                    }
                }
            } else {
                // Legacy pipeline: whisper-cpp segment matching
                if !whisperAvailable {
                    showError("whisper.cpp not found and advanced pipeline not available. "
                              + "Install whisper-cpp with: brew install whisper-cpp, "
                              + "or set up the advanced pipeline: cd Scripts && ./setup_alignment.sh")
                    isAligning = false
                    alignmentProgress = ""
                    return
                }
                let segments = try await WhisperAlignmentService.transcribe(
                    audioURL: audioURL
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = msg
                    }
                }

                aligned = WhisperAlignmentService.align(
                    segments: segments,
                    to: project.lyricBlocks,
                    mode: alignmentQualityMode
                ) { [weak self] msg in
                    Task { @MainActor in
                        self?.alignmentProgress = msg
                    }
                }
            }

            project.lyricBlocks = aligned
            project.touch()
            isDirty = true

            let matched = aligned.filter { ($0.confidence ?? 0) > 0.5 }.count
            statusMessage = "Alignment complete: \(matched)/\(aligned.count) blocks matched with good confidence."

            // Cleanup
            try? FileManager.default.removeItem(at: audioURL)

        } catch {
            showError(error.localizedDescription)
        }

        isAligning = false
        alignmentProgress = ""
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

            if let videoURL = project.sourceVideoURL,
               FileManager.default.fileExists(atPath: videoURL.path) {
                setupPlayer(url: videoURL)
            }

            statusMessage = "Project loaded: \(project.title)"
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
        statusMessage = "New project created."
    }

    // MARK: - Helpers

    func showError(_ message: String) {
        errorMessage = message
        showError = true
        statusMessage = "Error: \(message)"
    }
}
