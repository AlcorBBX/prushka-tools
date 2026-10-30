import Foundation

/// Local guardrails so a bad path, registry edit, or typo cannot freely run shell.
enum Safety {
    static let knownUnitIDs: Set<String> = [
        "web-dev", "web-prod",
        "autogen-stems-dev", "autogen-stems-prod",
        "desktop-dev", "mobile-dev",
        "api-memory"
    ]

    static let knownToolIDs: Set<String> = [
        "tab-source-fetch",
        "tab-source-fill",
        "demo-notes-from-lead"
    ]

    static let allowedScripts: Set<String> = [
        "up.sh", "down.sh", "status.sh"
    ]

    /// First argv token for registry tools / quality jobs (no raw shell).
    static let allowedToolBinaries: Set<String> = [
        "pnpm", "node", "npm", "bun", "npx", "sh", "/bin/sh"
    ]

    static let knownQualityJobIDs: Set<String> = Set(QualityCatalog.jobs.map(\.id))

    static let allowedScriptArgs: Set<String> = Set([
        "dev", "prod", "all",
        "web", "frontend", "autogen-stems", "desktop", "mobile", "api-memory",
        "--bg", "--json"
    ]).union(knownUnitIDs)

    static let knownGitRepoIDs: Set<String> = Set(GitCatalog.repos.map(\.id))

    enum Failure: LocalizedError {
        case invalidRepo
        case unknownScript(String)
        case scriptEscape
        case badScriptArg(String)
        case unknownUnit(String)
        case unknownTool(String)
        case unknownQualityJob(String)
        case badToolBinary(String)
        case badToolToken(String)
        case badToolValue(String)
        case cwdEscape
        case logEscape
        case badURL
        case unknownGitRepo(String)
        case missingGitRepo(String)
        case badGitPath(String)
        case missingBinary(String, hint: String)
        case agentFailed(String)
        case lazygitFailed(String)
        case gitFailed(String)
        case badCommitMessage(String)
        case missingLauncherSources
        case rebuildFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidRepo:
                "Checkout is not a Prushka repo (need scripts/registry.json, scripts/up.sh, front/package.json)."
            case .unknownScript(let name):
                "Refused unknown script: \(name)"
            case .scriptEscape:
                "Script path left the repo scripts/ folder."
            case .badScriptArg(let arg):
                "Refused script argument: \(arg)"
            case .unknownUnit(let id):
                "Unknown unit: \(id)"
            case .unknownTool(let id):
                "Unknown tool: \(id)"
            case .unknownQualityJob(let id):
                "Unknown quality job: \(id)"
            case .badToolBinary(let name):
                "Tool binary not allowed: \(name)"
            case .badToolToken(let token):
                "Unsafe token in tool command: \(token)"
            case .badToolValue(let value):
                "Unsafe tool value: \(value)"
            case .cwdEscape:
                "Tool working directory is outside the checkout."
            case .logEscape:
                "Log path is outside .run/logs."
            case .badURL:
                "Open is limited to local http(s) URLs."
            case .unknownGitRepo(let id):
                "Unknown git repo: \(id)"
            case .missingGitRepo(let id):
                "No .git under \(id)/ — skip or clone that nested repo."
            case .badGitPath(let path):
                "Refused git path: \(path)"
            case .missingBinary(let name, let hint):
                "\(name) not found on PATH. \(hint)"
            case .agentFailed(let detail):
                "Commit message generation failed: \(detail)"
            case .lazygitFailed(let detail):
                "Could not open lazygit: \(detail)"
            case .gitFailed(let detail):
                "git failed: \(detail)"
            case .badCommitMessage(let detail):
                "Invalid commit message: \(detail)"
            case .missingLauncherSources:
                "Launcher sources missing (need tools/macos-dev-launcher/Package.swift and Scripts/package-app.sh)."
            case .rebuildFailed(let detail):
                "Rebuild failed: \(detail)"
            }
        }
    }

    /// Message for `git commit -F`; rejects empty / oversized / control-laden text.
    static func sanitizeCommitMessage(_ raw: String) -> Result<String, Failure> {
        let message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return .failure(.badCommitMessage("empty"))
        }
        guard message.count <= 8_000 else {
            return .failure(.badCommitMessage("too long (max 8000 characters)"))
        }
        if message.contains("\0") {
            return .failure(.badCommitMessage("contains NUL"))
        }
        return .success(message)
    }

    /// Resolves `tools/macos-dev-launcher` + allowlisted `Scripts/package-app.sh` under the checkout.
    static func launcherPackageScript(root: URL) -> Result<(script: URL, cwd: URL, app: URL), Failure> {
        switch containedDirectory(relative: "tools/macos-dev-launcher", root: root) {
        case .failure(let error):
            return .failure(error)
        case .success(let launcherRoot):
            let package = launcherRoot.appendingPathComponent("Package.swift")
            let script = launcherRoot
                .appendingPathComponent("Scripts")
                .appendingPathComponent("package-app.sh")
                .standardizedFileURL
            let scriptsDir = launcherRoot.appendingPathComponent("Scripts").standardizedFileURL
            guard FileManager.default.fileExists(atPath: package.path),
                  FileManager.default.fileExists(atPath: script.path)
            else {
                return .failure(.missingLauncherSources)
            }
            let resolved = script.resolvingSymlinksInPath()
            let scriptsResolved = scriptsDir.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(scriptsResolved.path + "/")
                || resolved.path == scriptsResolved.appendingPathComponent("package-app.sh").path
            else {
                return .failure(.scriptEscape)
            }
            let app = launcherRoot
                .appendingPathComponent("dist")
                .appendingPathComponent("Prushka L.app")
            return .success((script, launcherRoot, app))
        }
    }

    /// Resolves a known nested git repo under the Prushka checkout.
    static func gitRepoURL(repo: NestedGitRepo, root: URL) -> Result<URL, Failure> {
        guard knownGitRepoIDs.contains(repo.id),
              let canonical = GitCatalog.repo(id: repo.id),
              canonical == repo
        else {
            return .failure(.unknownGitRepo(repo.id))
        }
        switch containedDirectory(relative: repo.relativePath, root: root) {
        case .failure(let error):
            return .failure(error)
        case .success(let cwd):
            let gitDir = cwd.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: gitDir.path, isDirectory: &isDir)
            // .git can be a directory or a file (worktree / submodule pointer).
            guard exists else {
                return .failure(.missingGitRepo(repo.relativePath))
            }
            return .success(cwd)
        }
    }

    static func gitRepoAvailable(repo: NestedGitRepo, root: URL) -> Bool {
        if case .success = gitRepoURL(repo: repo, root: root) {
            return true
        }
        return false
    }

    /// Relative paths only; no shell metacharacters or path escape.
    static func sanitizeGitPaths(_ paths: [String]) -> Result<[String], Failure> {
        guard !paths.isEmpty else {
            return .failure(.badGitPath("(empty)"))
        }
        var result: [String] = []
        result.reserveCapacity(paths.count)
        for raw in paths {
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, path.count <= 512 else {
                return .failure(.badGitPath(raw))
            }
            guard !path.hasPrefix("/"),
                  !path.contains(".."),
                  !path.contains("~"),
                  !path.contains("\0")
            else {
                return .failure(.badGitPath(path))
            }
            guard isSafeCommandToken(path) || isSafeGitPathToken(path) else {
                return .failure(.badGitPath(path))
            }
            result.append(path)
        }
        return .success(result)
    }

    /// Like tool tokens but allows `/` in relative paths.
    private static func isSafeGitPathToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 512 else { return false }
        if token.contains("\0") || token.contains("\n") || token.contains("\r") { return false }
        let banned = CharacterSet(charactersIn: ";|&$`<>\\\"'(){}[]!*?\n\r\t")
        if token.unicodeScalars.contains(where: { banned.contains($0) }) { return false }
        if token.contains("..") { return false }
        return true
    }

    static func requireBinaryOnPath(_ name: String, extraPath: String?) -> Result<String, Failure> {
        let allowed = Set(["git", "agent", "lazygit"])
        guard allowed.contains(name) else {
            return .failure(.badToolBinary(name))
        }
        if let resolved = which(name, extraPath: extraPath) {
            return .success(resolved)
        }
        let hint: String
        switch name {
        case "agent":
            hint = "Install Cursor CLI (https://cursor.com/install) and ensure agent is on your login PATH."
        case "lazygit":
            hint = "Install with: brew install lazygit"
        case "git":
            hint = "Install Xcode Command Line Tools or Homebrew git."
        default:
            hint = ""
        }
        return .failure(.missingBinary(name, hint: hint))
    }

    static func which(_ name: String, extraPath: String?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        var env = ProcessInfo.processInfo.environment
        if let extraPath, !extraPath.isEmpty {
            if let existing = env["PATH"], !existing.isEmpty {
                env["PATH"] = extraPath + ":" + existing
            } else {
                env["PATH"] = extraPath
            }
        }
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let line = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
        guard let line, line.contains("/") else { return nil }
        return line
    }

    static func validateRepo(_ path: String) -> Result<URL, Failure> {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.invalidRepo)
        }
        let markers = [
            "scripts/registry.json",
            "scripts/up.sh",
            "scripts/down.sh",
            "scripts/status.sh",
            "front/package.json"
        ]
        for marker in markers {
            let item = url.appendingPathComponent(marker)
            guard FileManager.default.fileExists(atPath: item.path) else {
                return .failure(.invalidRepo)
            }
        }
        return .success(url)
    }

    static func scriptURL(named name: String, root: URL) -> Result<URL, Failure> {
        let base = (name as NSString).lastPathComponent
        guard allowedScripts.contains(base), base == name, !name.contains("/") else {
            return .failure(.unknownScript(name))
        }
        let url = root.appendingPathComponent("scripts").appendingPathComponent(base).standardizedFileURL
        let scriptsDir = root.appendingPathComponent("scripts").standardizedFileURL
        guard url.path.hasPrefix(scriptsDir.path + "/") || url.path == scriptsDir.appendingPathComponent(base).path else {
            return .failure(.scriptEscape)
        }
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(scriptsDir.resolvingSymlinksInPath().path + "/")
            || resolved.path == scriptsDir.resolvingSymlinksInPath().appendingPathComponent(base).path
        else {
            return .failure(.scriptEscape)
        }
        guard FileManager.default.isExecutableFile(atPath: resolved.path)
            || FileManager.default.fileExists(atPath: resolved.path)
        else {
            return .failure(.unknownScript(name))
        }
        return .success(resolved)
    }

    static func validateScriptArguments(_ args: [String]) -> Result<[String], Failure> {
        for arg in args {
            if allowedScriptArgs.contains(arg) { continue }
            if knownUnitIDs.contains(arg) { continue }
            return .failure(.badScriptArg(arg))
        }
        return .success(args)
    }

    static func validateUnitID(_ id: String) -> Result<String, Failure> {
        knownUnitIDs.contains(id) ? .success(id) : .failure(.unknownUnit(id))
    }

    static func validateTool(_ tool: RegistryTool, root: URL) -> Result<(command: [String], cwd: URL), Failure> {
        guard knownToolIDs.contains(tool.id) else {
            return .failure(.unknownTool(tool.id))
        }
        guard !tool.command.isEmpty else {
            return .failure(.badToolBinary(""))
        }
        let binary = tool.command[0]
        guard allowedToolBinaries.contains(binary) else {
            return .failure(.badToolBinary(binary))
        }
        for token in tool.command {
            guard isSafeCommandToken(token) else {
                return .failure(.badToolToken(token))
            }
        }
        for arg in tool.args {
            guard arg.flag.hasPrefix("--"), isSafeCommandToken(arg.flag) else {
                return .failure(.badToolToken(arg.flag))
            }
        }
        switch containedDirectory(relative: tool.cwd, root: root) {
        case .failure(let error):
            return .failure(error)
        case .success(let cwd):
            return .success((tool.command, cwd))
        }
    }

    static func validateQualityJob(_ job: QualityJob, root: URL) -> Result<(command: [String], cwd: URL), Failure> {
        guard knownQualityJobIDs.contains(job.id),
              let canonical = QualityCatalog.job(id: job.id),
              canonical == job
        else {
            return .failure(.unknownQualityJob(job.id))
        }
        guard !job.command.isEmpty else {
            return .failure(.badToolBinary(""))
        }
        let binary = job.command[0]
        guard allowedToolBinaries.contains(binary) else {
            return .failure(.badToolBinary(binary))
        }
        for token in job.command {
            guard isSafeCommandToken(token) else {
                return .failure(.badToolToken(token))
            }
        }
        return containedDirectory(relative: job.cwd, root: root).map { (job.command, $0) }
    }

    static func sanitizeToolValue(_ raw: String, type: String) -> Result<String, Failure> {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .failure(.badToolValue(raw)) }
        guard value.count <= 64 else { return .failure(.badToolValue(value)) }
        if type == "number" {
            guard value.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
                return .failure(.badToolValue(value))
            }
            return .success(value)
        }
        // demo slugs / strings: letters, digits, dash, underscore
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .failure(.badToolValue(value))
        }
        return .success(value)
    }

    static func openableURL(_ string: String) -> Result<URL, Failure> {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1" || host == "::1"
        else {
            return .failure(.badURL)
        }
        return .success(url)
    }

    static func logFileURL(unitID: String, root: URL, preferred: String?) -> Result<URL, Failure> {
        switch validateUnitID(unitID) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }
        let logsDir = root.appendingPathComponent(".run/logs").standardizedFileURL
        if let preferred, !preferred.isEmpty {
            let candidate = URL(fileURLWithPath: preferred).resolvingSymlinksInPath().standardizedFileURL
            if candidate.path.hasPrefix(logsDir.resolvingSymlinksInPath().path + "/")
                || candidate.deletingLastPathComponent().path == logsDir.resolvingSymlinksInPath().path
            {
                return .success(candidate)
            }
            // Fall through to the canonical path if preferred escapes.
        }
        let file = logsDir.appendingPathComponent("\(unitID).log").standardizedFileURL
        guard file.path.hasPrefix(logsDir.path + "/") || file.deletingLastPathComponent().path == logsDir.path else {
            return .failure(.logEscape)
        }
        return .success(file)
    }

    private static func containedDirectory(relative: String, root: URL) -> Result<URL, Failure> {
        guard !relative.hasPrefix("/"),
              !relative.contains(".."),
              !relative.contains("~"),
              !relative.contains("\0")
        else {
            return .failure(.cwdEscape)
        }
        let cwd = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        let rootResolved = root.resolvingSymlinksInPath().standardizedFileURL
        guard cwd.path == rootResolved.path || cwd.path.hasPrefix(rootResolved.path + "/") else {
            return .failure(.cwdEscape)
        }
        return .success(cwd)
    }

    private static func isSafeCommandToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.count <= 128 else { return false }
        if token.contains("\0") || token.contains("\n") || token.contains("\r") { return false }
        // No shell metacharacters / path escape.
        let banned = CharacterSet(charactersIn: ";|&$`<>\\\"'(){}[]!*?\n\r\t")
        if token.unicodeScalars.contains(where: { banned.contains($0) }) { return false }
        if token.contains("..") { return false }
        return true
    }
}
