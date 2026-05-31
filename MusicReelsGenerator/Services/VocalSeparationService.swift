import CryptoKit
import Foundation

enum VocalSeparationError: LocalizedError {
    case demucsNotFound
    case extractionFailed(String)
    case separationFailed(String)
    case outputNotFound
    case resampleFailed(String)
    case ffmpegNotFound

    var errorDescription: String? {
        switch self {
        case .demucsNotFound:
            return "Demucs not found. Install with: pip3 install demucs"
        case .extractionFailed(let m):
            return "Audio extraction for vocal separation failed: \(m)"
        case .separationFailed(let m):
            return "Vocal separation failed: \(m)"
        case .outputNotFound:
            return "Demucs produced no vocal output (expected vocals.wav)."
        case .resampleFailed(let m):
            return "Vocal stem resample failed: \(m)"
        case .ffmpegNotFound:
            return "FFmpeg not found. Install with: brew install ffmpeg"
        }
    }
}

enum VocalSeparationService {
    /// Cache directory for processed 16 kHz mono vocal stems.
    /// Keyed by a content fingerprint of the source video.
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("MusicReelsGenerator/vocals", isDirectory: true)
    }

    /// Whether demucs is available on this system (CLI binary or Python module).
    /// Probes Python with `import demucs` so it works whether the user installed
    /// the standalone CLI (`pip install demucs` exposes `demucs`) or only the module.
    static var isAvailable: Bool {
        return findDemucsBinary() != nil || findDemucsModule() != nil
    }

    // MARK: - Detection

    private static func findDemucsBinary() -> String? {
        var candidates: [String] = [
            "/opt/homebrew/bin/demucs",
            "/usr/local/bin/demucs",
            "\(NSHomeDirectory())/.local/bin/demucs"
        ]
        if let onPath = ProcessRunner.which("demucs") {
            candidates.append(onPath)
        }
        // python.org framework installs land pip console scripts here.
        // GUI apps launched via `open` don't inherit the shell PATH, so we
        // probe the framework directly instead of relying on `which`.
        let frameworkRoot = "/Library/Frameworks/Python.framework/Versions"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: frameworkRoot) {
            for v in versions where v != "Current" {
                candidates.append("\(frameworkRoot)/\(v)/bin/demucs")
            }
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func findDemucsModule() -> String? {
        guard let py = ProcessRunner.findPython() else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: py)
        task.arguments = ["-c", "import demucs"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0 ? py : nil
        } catch {
            return nil
        }
    }

    // MARK: - Public entry point

    /// Produce a 16 kHz mono WAV containing only vocals, ready for whisper.cpp.
    /// Result is cached at `~/Library/Caches/MusicReelsGenerator/vocals/<fingerprint>.wav`,
    /// so repeated alignments of the same video skip the demucs run entirely.
    static func prepareVocalAudio(
        fromVideo videoURL: URL,
        outputURL: URL,
        onProgress: ((String) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        onProgress?("Fingerprinting video for vocal cache...")
        let key = try fingerprint(of: videoURL)
        let cached = cacheDirectory.appendingPathComponent("\(key).wav")

        if fm.fileExists(atPath: cached.path) {
            try? fm.removeItem(at: outputURL)
            try fm.copyItem(at: cached, to: outputURL)
            onProgress?("Reusing cached vocal stem.")
            return
        }

        guard let ffmpeg = ProcessRunner.findFFmpeg() else {
            throw VocalSeparationError.ffmpegNotFound
        }

        let workDir = NSTemporaryDirectory() + "vocalSep_\(UUID().uuidString)/"
        try fm.createDirectory(atPath: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: workDir) }

        // Stage A: extract 44.1 kHz stereo WAV — demucs needs full-fidelity input
        // (its training distribution is stereo music, not 16 kHz mono speech).
        let stereoWav = workDir + "input.wav"
        onProgress?("Extracting full-fidelity audio for demucs...")
        let extractResult = try await ProcessRunner.run(ffmpeg, arguments: [
            "-i", videoURL.path,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "44100",
            "-ac", "2",
            "-y",
            stereoWav
        ])
        guard extractResult.succeeded else {
            throw VocalSeparationError.extractionFailed(extractResult.stderr)
        }

        // Stage B: run demucs with two-stem mode (vocals / no_vocals).
        onProgress?("Separating vocals with demucs (1–5 minutes on first run)...")
        let demucsOutDir = workDir + "demucs/"
        try fm.createDirectory(atPath: demucsOutDir, withIntermediateDirectories: true)

        let (executable, prefixArgs) = try resolveDemucsCommand()
        let demucsArgs = prefixArgs + [
            "--two-stems", "vocals",
            "-o", demucsOutDir,
            "--filename", "{stem}.{ext}",
            stereoWav
        ]
        let demucsResult = try await ProcessRunner.run(executable, arguments: demucsArgs, timeout: 900)
        guard demucsResult.succeeded else {
            throw VocalSeparationError.separationFailed(String(demucsResult.stderr.suffix(500)))
        }

        guard let vocalsPath = findFile(named: "vocals.wav", under: demucsOutDir) else {
            throw VocalSeparationError.outputNotFound
        }

        // Stage C: resample to 16 kHz mono — whisper.cpp requires this.
        onProgress?("Resampling vocal stem for whisper...")
        try? fm.removeItem(at: outputURL)
        let resampleResult = try await ProcessRunner.run(ffmpeg, arguments: [
            "-i", vocalsPath,
            "-acodec", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            "-y",
            outputURL.path
        ])
        guard resampleResult.succeeded else {
            throw VocalSeparationError.resampleFailed(resampleResult.stderr)
        }

        // Cache. copyItem to avoid leaving the user without an output if cache fails.
        try? fm.removeItem(at: cached)
        try? fm.copyItem(at: outputURL, to: cached)

        onProgress?("Vocal separation complete.")
    }

    // MARK: - Helpers

    private static func resolveDemucsCommand() throws -> (executable: String, prefixArgs: [String]) {
        if let bin = findDemucsBinary() {
            return (bin, [])
        }
        if let py = findDemucsModule() {
            return (py, ["-m", "demucs"])
        }
        throw VocalSeparationError.demucsNotFound
    }

    private static func findFile(named name: String, under root: String) -> String? {
        let lowered = name.lowercased()
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return nil }
        while let item = enumerator.nextObject() as? String {
            if (item as NSString).lastPathComponent.lowercased() == lowered {
                return (root as NSString).appendingPathComponent(item)
            }
        }
        return nil
    }

    /// Cheap content fingerprint: path + size + mtime + first 1 MB + last 1 MB.
    /// Full SHA256 of a 1 GB video would block ~10 s on HDDs; this stays under
    /// 100 ms regardless of file size, and collision risk is negligible for
    /// real-world music videos.
    private static func fingerprint(of url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        var hasher = SHA256()
        hasher.update(data: Data("\(url.path):\(size):\(mtime)".utf8))

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkBytes = 1024 * 1024
        let head = try handle.read(upToCount: chunkBytes) ?? Data()
        hasher.update(data: head)

        if size > UInt64(2 * chunkBytes) {
            try handle.seek(toOffset: size - UInt64(chunkBytes))
            let tail = try handle.read(upToCount: chunkBytes) ?? Data()
            hasher.update(data: tail)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
