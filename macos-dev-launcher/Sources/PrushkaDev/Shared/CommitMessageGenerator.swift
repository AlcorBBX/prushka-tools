import Foundation

enum CommitMessageGenerator {
    static let maxDiffChars = 48_000
    static let maxStatusChars = 8_000
    static let maxLogChars = 4_000

    static func generate(
        repo: NestedGitRepo,
        root: URL,
        extraPath: String?,
        statusText: String,
        cachedDiff: String,
        shortLog: String
    ) async -> Result<String, Safety.Failure> {
        let cwd: URL
        switch Safety.gitRepoURL(repo: repo, root: root) {
        case .failure(let error):
            return .failure(error)
        case .success(let url):
            cwd = url
        }

        switch Safety.requireBinaryOnPath("agent", extraPath: extraPath) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        let prompt = buildPrompt(
            repoLabel: repo.label,
            statusText: truncate(statusText, max: maxStatusChars),
            cachedDiff: truncate(cachedDiff, max: maxDiffChars),
            shortLog: truncate(shortLog, max: maxLogChars)
        )

        // Ask mode is read-only: no git commit / write tools.
        // --trust skips the interactive workspace-trust prompt required in -p mode.
        let arguments = [
            "agent",
            "-p",
            "--trust",
            "--mode", "ask",
            "--output-format", "text",
            prompt
        ]

        let output = await ProcessRunner.run(
            arguments: arguments,
            cwd: cwd,
            extraPath: extraPath,
            timeout: .seconds(180)
        )

        if output.cancelled {
            return .failure(.agentFailed("Cancelled."))
        }
        if output.code != 0 {
            let detail = output.combined.isEmpty ? "exit \(output.code)" : output.combined
            return .failure(.agentFailed(Self.clip(detail)))
        }

        let message = sanitizeMessage(output.stdout)
        guard !message.isEmpty else {
            return .failure(.agentFailed("agent returned an empty message."))
        }
        return .success(message)
    }

    static func buildPrompt(
        repoLabel: String,
        statusText: String,
        cachedDiff: String,
        shortLog: String
    ) -> String {
        """
        You are writing a git commit message for the nested repo "\(repoLabel)" in a Prushka checkout.

        Required format — Conventional Commits WITH a scope in parentheses:
          type(scope): Subject line in sentence case or imperative mood

        Then a blank line, then a short body as "-" bullets when there is more than one notable change.

        Scope rules:
        - ALWAYS include a scope when staged paths imply a module, type, feature, or folder (e.g. ProcessRunner, GitView, Safety, package-app).
        - Prefer the primary Swift type / file stem / feature name from the staged diff, not the repo name "\(repoLabel)".
        - If several areas change, pick the dominant one; do not omit the scope.
        - Example header: feat(ProcessRunner): Enhance PATH handling for GUI applications

        Match the tone of recent commits in the log (header + bullets when that style appears).
        Output ONLY the commit message text. No markdown fences, no quotes, no explanation, no trailing commentary.
        If there are no staged changes, say so in one short sentence.

        Recent commits:
        \(shortLog.isEmpty ? "(none)" : shortLog)

        Status:
        \(statusText.isEmpty ? "(empty)" : statusText)

        Staged diff:
        \(cachedDiff.isEmpty ? "(no staged diff)" : cachedDiff)
        """
    }

    static func sanitizeMessage(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var body = Array(lines.dropFirst())
            if let last = body.last, last.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") {
                body.removeLast()
            }
            text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        return String(text.prefix(max)) + "\n…(truncated)"
    }

    private static func clip(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 800 { return trimmed }
        return String(trimmed.prefix(800)) + "…"
    }
}

enum LazygitLauncher {
    static func open(repo: NestedGitRepo, root: URL, extraPath: String?) -> Result<Void, Safety.Failure> {
        let cwd: URL
        switch Safety.gitRepoURL(repo: repo, root: root) {
        case .failure(let error):
            return .failure(error)
        case .success(let url):
            cwd = url
        }

        switch Safety.requireBinaryOnPath("lazygit", extraPath: extraPath) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // Escape for AppleScript string: backslash and double-quote.
        let path = cwd.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
          activate
          do script "cd \\"\(path)\\" && lazygit"
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardInput = FileHandle.nullDevice
        let err = Pipe()
        process.standardError = err
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failure(.lazygitFailed("Could not run osascript: \(error.localizedDescription)"))
        }
        if process.terminationStatus != 0 {
            let detail = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(
                .lazygitFailed(
                    detail.isEmpty
                        ? "Terminal.app / osascript failed (\(process.terminationStatus)). Open Terminal in \(cwd.path) and run lazygit."
                        : detail
                )
            )
        }
        return .success(())
    }
}
