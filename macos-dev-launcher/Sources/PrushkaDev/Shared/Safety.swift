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

    /// First argv token for registry tools (no raw shell).
    static let allowedToolBinaries: Set<String> = [
        "pnpm", "node", "npm", "bun", "npx"
    ]

    static let allowedScriptArgs: Set<String> = Set([
        "dev", "prod", "all",
        "web", "frontend", "autogen-stems", "desktop", "mobile", "api-memory",
        "--bg", "--json"
    ]).union(knownUnitIDs)

    enum Failure: LocalizedError {
        case invalidRepo
        case unknownScript(String)
        case scriptEscape
        case badScriptArg(String)
        case unknownUnit(String)
        case unknownTool(String)
        case badToolBinary(String)
        case badToolToken(String)
        case badToolValue(String)
        case cwdEscape
        case logEscape
        case badURL

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
            }
        }
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
