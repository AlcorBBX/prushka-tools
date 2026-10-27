import Foundation

struct CommandOutput: Sendable, Equatable {
    var code: Int32
    var stdout: String
    var stderr: String
    var cancelled: Bool

    var combined: String {
        [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// Retains a live `Process` so the UI can terminate it.
final class ManagedProcess: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var terminated = false

    func terminate() {
        lock.lock()
        terminated = true
        lock.unlock()
        if process.isRunning {
            process.terminate()
        }
    }

    var wasTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }
}

/// Runs commands with a PATH taken once from an interactive login shell, so `pnpm` / `go` / `bun`
/// resolve (bun is often exported from `.zshrc`, which non-interactive `zsh -lc` skips).
enum ProcessRunner {
    static func captureLoginPath(timeout: Duration = .seconds(8)) async -> String {
        // `-i` loads `.zshrc` where bun/nvm/asdf hooks usually live; GUI apps otherwise miss them.
        let output = await run(
            arguments: ["/bin/zsh", "-ilc", "printf %s \"$PATH\""],
            cwd: nil,
            extraPath: developerPath(),
            timeout: timeout
        )
        let line = output.stdout.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            return mergePaths(trimmed, developerPath())
        }
        return developerPath()
    }

    static func run(
        arguments: [String],
        cwd: URL?,
        extraPath: String?,
        timeout: Duration? = nil,
        coalesce: Duration? = .milliseconds(80),
        onChunk: (@Sendable (String) -> Void)? = nil,
        onStart: (@Sendable (ManagedProcess) -> Void)? = nil
    ) async -> CommandOutput {
        // Hop off the caller's actor (often MainActor) before any Process I/O.
        await Task.detached(priority: .userInitiated) {
            await execute(
                arguments: arguments,
                cwd: cwd,
                extraPath: extraPath,
                timeout: timeout,
                coalesce: coalesce,
                onChunk: onChunk,
                onStart: onStart
            )
        }.value
    }

    private static func execute(
        arguments: [String],
        cwd: URL?,
        extraPath: String?,
        timeout: Duration?,
        coalesce: Duration?,
        onChunk: (@Sendable (String) -> Void)?,
        onStart: (@Sendable (ManagedProcess) -> Void)?
    ) async -> CommandOutput {
        let managed = ManagedProcess()
        let process = managed.process
        let stdoutReader = PipeReader(Pipe())
        let stderrReader = PipeReader(Pipe())

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = cwd
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutReader.pipe
        process.standardError = stderrReader.pipe
        process.environment = environment(extraPath: extraPath)
        process.qualityOfService = .userInitiated

        let pump: StreamPump?
        let chunkHandler: (@Sendable (String) -> Void)?
        if let onChunk {
            if let coalesce, coalesce > .zero {
                let created = StreamPump(interval: coalesce, emit: onChunk)
                pump = created
                chunkHandler = { created.push($0) }
            } else {
                pump = nil
                chunkHandler = onChunk
            }
        } else {
            pump = nil
            chunkHandler = nil
        }

        let stdoutBox = LockedString()
        let stderrBox = LockedString()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBox.set(stdoutReader.readAll(onChunk: chunkHandler))
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.set(stderrReader.readAll(onChunk: chunkHandler))
            readers.leave()
        }

        onStart?(managed)

        let exitCode: Int32
        do {
            try await waitForExit(process, timeout: timeout, managed: managed)
            exitCode = process.terminationStatus
        } catch {
            stdoutReader.close()
            stderrReader.close()
            await readers.wait()
            pump?.flush()
            return CommandOutput(code: 127, stdout: "", stderr: error.localizedDescription, cancelled: false)
        }

        await readers.wait()
        pump?.flush()
        return CommandOutput(
            code: exitCode,
            stdout: stdoutBox.get(),
            stderr: stderrBox.get(),
            cancelled: managed.wasTerminated
        )
    }

    private static func waitForExit(
        _ process: Process,
        timeout: Duration?,
        managed: ManagedProcess
    ) async throws {
        try process.run()
        if let timeout {
            Task.detached {
                try? await Task.sleep(for: timeout)
                managed.terminate()
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeGate()
            process.terminationHandler = { _ in
                once.resume(continuation)
            }
            if !process.isRunning {
                once.resume(continuation)
            }
        }
    }

    private static func environment(extraPath: String?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let login = extraPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = login.isEmpty ? (env["PATH"] ?? "") : login
        env["PATH"] = mergePaths(base, developerPath())
        env["NO_COLOR"] = "1"
        // Bun and some CLIs read HOME; keep it explicit when the parent env is sparse.
        if env["HOME"]?.isEmpty != false {
            env["HOME"] = NSHomeDirectory()
        }
        return env
    }

    /// Directories GUI-launched apps often miss compared to a Terminal session.
    private static func developerPath() -> String {
        let home = NSHomeDirectory()
        return [
            "\(home)/.bun/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
    }

    private static func mergePaths(_ parts: String...) -> String {
        var seen = Set<String>()
        var ordered: [String] = []
        for part in parts {
            for raw in part.split(separator: ":", omittingEmptySubsequences: true) {
                let item = String(raw)
                if seen.insert(item).inserted {
                    ordered.append(item)
                }
            }
        }
        return ordered.joined(separator: ":")
    }
}

/// Batches stdout/stderr chunks so the UI is not flooded with MainActor updates.
private final class StreamPump: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var scheduled = false
    private let interval: Duration
    private let emit: @Sendable (String) -> Void

    init(interval: Duration, emit: @escaping @Sendable (String) -> Void) {
        self.interval = interval
        self.emit = emit
    }

    func push(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        buffer += chunk
        let shouldSchedule = !scheduled
        if shouldSchedule {
            scheduled = true
        }
        lock.unlock()
        guard shouldSchedule else { return }
        Task.detached(priority: .utility) { [interval] in
            try? await Task.sleep(for: interval)
            self.flush()
        }
    }

    func flush() {
        lock.lock()
        let batch = buffer
        buffer = ""
        scheduled = false
        lock.unlock()
        guard !batch.isEmpty else { return }
        emit(batch)
    }
}

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func set(_ newValue: String) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private extension DispatchGroup {
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            notify(queue: .global(qos: .userInitiated)) {
                continuation.resume()
            }
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        let should = !resumed
        resumed = true
        lock.unlock()
        if should {
            continuation.resume()
        }
    }
}

private final class PipeReader: @unchecked Sendable {
    let pipe: Pipe

    init(_ pipe: Pipe) {
        self.pipe = pipe
    }

    func close() {
        try? pipe.fileHandleForReading.close()
    }

    func readAll(onChunk: (@Sendable (String) -> Void)?) -> String {
        let handle = pipe.fileHandleForReading
        var text = ""
        while true {
            let data = handle.availableData
            if data.isEmpty {
                break
            }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else {
                continue
            }
            text += chunk
            if text.count > 200_000 {
                text.removeFirst(text.count - 160_000)
            }
            onChunk?(chunk)
        }
        return text
    }
}
