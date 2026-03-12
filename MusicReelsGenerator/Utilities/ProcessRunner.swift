import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let pid: Int32

    var succeeded: Bool { exitCode == 0 }
}

/// Thread-safe container for pipe data. DispatchGroup provides the actual
/// synchronization; this wrapper satisfies the Swift concurrency checker.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}

enum ProcessRunner {
    /// Run a subprocess asynchronously.
    ///
    /// IMPORTANT: stdout and stderr are drained continuously on background threads
    /// to prevent pipe-buffer deadlocks. The old implementation read pipes inside
    /// the terminationHandler, which caused deadlocks when the subprocess produced
    /// more than ~64KB of output — the process would block on write, and the
    /// terminationHandler would never fire.
    static func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> ProcessResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let execName = (executable as NSString).lastPathComponent

        print("[ProcessRunner] Launching: \(execName) \(arguments.prefix(4).joined(separator: " "))\(arguments.count > 4 ? " ..." : "")")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            if let dir = currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Drain pipes on background threads BEFORE termination to prevent deadlock.
            // readDataToEndOfFile() blocks until the write end is closed (process exit).
            let stdoutBox = DataBox()
            let stderrBox = DataBox()
            let readGroup = DispatchGroup()

            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stdoutBox.value = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }

            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stderrBox.value = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }

            // After process terminates AND pipes are fully drained, resume.
            process.terminationHandler = { proc in
                // Wait for pipe readers to finish (they complete shortly after process exits)
                readGroup.wait()

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let pid = proc.processIdentifier
                let exitCode = proc.terminationStatus

                let stdoutStr = String(data: stdoutBox.value, encoding: .utf8) ?? ""
                let stderrStr = String(data: stderrBox.value, encoding: .utf8) ?? ""

                if exitCode == 0 {
                    print("[ProcessRunner] \(execName) (pid=\(pid)) completed successfully in \(String(format: "%.1f", elapsed))s")
                } else {
                    print("[ProcessRunner] \(execName) (pid=\(pid)) FAILED exit=\(exitCode) in \(String(format: "%.1f", elapsed))s")
                    let stderrSnippet = String(stderrStr.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stderrSnippet.isEmpty {
                        print("[ProcessRunner] stderr tail: \(stderrSnippet)")
                    }
                }

                let result = ProcessResult(
                    exitCode: exitCode,
                    stdout: stdoutStr,
                    stderr: stderrStr,
                    pid: pid
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
                let pid = process.processIdentifier
                print("[ProcessRunner] \(execName) started with pid=\(pid)")

                // Timeout watchdog
                if let timeout = timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
                        guard let p = process, p.isRunning else { return }
                        print("[ProcessRunner] WARNING: \(execName) (pid=\(pid)) exceeded timeout of \(Int(timeout))s — terminating")
                        p.terminate()
                    }
                }
            } catch {
                print("[ProcessRunner] LAUNCH FAILED for \(execName): \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }

    /// Run a subprocess with live stderr streaming.
    /// Each line of stderr is delivered via `onStderrLine` as it arrives.
    /// This prevents the "no progress shown until completion" problem.
    static func runStreaming(
        _ executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        timeout: TimeInterval? = nil,
        onStderrLine: @escaping (String) -> Void
    ) async throws -> ProcessResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let execName = (executable as NSString).lastPathComponent

        print("[ProcessRunner] Launching (streaming): \(execName)")

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            if let dir = currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: dir)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBox = DataBox()
            let stderrBox = DataBox()
            let readGroup = DispatchGroup()

            // Read stdout in background (no streaming needed)
            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                stdoutBox.value = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                readGroup.leave()
            }

            // Read stderr with line-by-line streaming
            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = stderrPipe.fileHandleForReading
                var lineBuffer = Data()

                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break } // EOF

                    stderrBox.value.append(chunk)
                    lineBuffer.append(chunk)

                    // Extract complete lines and deliver them
                    while let newlineRange = lineBuffer.range(of: Data([0x0A])) { // \n
                        let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineRange.lowerBound)
                        lineBuffer.removeSubrange(lineBuffer.startIndex...newlineRange.lowerBound)

                        if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                            onStderrLine(line)
                        }
                    }
                }

                // Flush remaining buffer
                if !lineBuffer.isEmpty, let line = String(data: lineBuffer, encoding: .utf8), !line.isEmpty {
                    onStderrLine(line)
                }

                readGroup.leave()
            }

            process.terminationHandler = { proc in
                readGroup.wait()

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let pid = proc.processIdentifier
                let exitCode = proc.terminationStatus

                let stdoutStr = String(data: stdoutBox.value, encoding: .utf8) ?? ""
                let stderrStr = String(data: stderrBox.value, encoding: .utf8) ?? ""

                if exitCode == 0 {
                    print("[ProcessRunner] \(execName) (pid=\(pid)) completed in \(String(format: "%.1f", elapsed))s")
                } else {
                    print("[ProcessRunner] \(execName) (pid=\(pid)) FAILED exit=\(exitCode) in \(String(format: "%.1f", elapsed))s")
                    let snippet = String(stderrStr.suffix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !snippet.isEmpty { print("[ProcessRunner] stderr tail: \(snippet)") }
                }

                continuation.resume(returning: ProcessResult(
                    exitCode: exitCode,
                    stdout: stdoutStr,
                    stderr: stderrStr,
                    pid: pid
                ))
            }

            do {
                try process.run()
                let pid = process.processIdentifier
                print("[ProcessRunner] \(execName) started with pid=\(pid)")

                if let timeout = timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
                        guard let p = process, p.isRunning else { return }
                        print("[ProcessRunner] WARNING: \(execName) (pid=\(pid)) exceeded timeout \(Int(timeout))s — terminating")
                        p.terminate()
                    }
                }
            } catch {
                print("[ProcessRunner] LAUNCH FAILED for \(execName): \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }

    static func which(_ command: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
    }

    static func findFFmpeg() -> String? {
        let paths = [
            ProcessRunner.which("ffmpeg"),
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ]
        return paths.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func findWhisper() -> String? {
        let paths = [
            ProcessRunner.which("whisper-cli"),
            ProcessRunner.which("whisper-cpp"),
            "/opt/homebrew/bin/whisper-cli",
            "/opt/homebrew/bin/whisper-cpp",
            "/usr/local/bin/whisper-cli",
            "/usr/local/bin/whisper-cpp"
        ]
        return paths.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    static func findPython() -> String? {
        let paths = [
            ProcessRunner.which("python3"),
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        return paths.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }
}
