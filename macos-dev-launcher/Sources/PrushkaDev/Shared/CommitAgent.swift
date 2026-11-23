import Foundation

/// CLI agent that drafts commit messages from the staged diff.
enum CommitAgentProvider: String, CaseIterable, Identifiable, Sendable {
    case cursor
    case claude

    static let defaultsKey = "commitAgentProvider"
    static let fallback: CommitAgentProvider = .cursor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cursor: "Cursor"
        case .claude: "Claude Code"
        }
    }

    /// Binary name looked up on the login PATH.
    var binaryName: String {
        switch self {
        case .cursor: "agent"
        case .claude: "claude"
        }
    }

    var installHint: String {
        switch self {
        case .cursor:
            "Install Cursor CLI (https://cursor.com/install) and ensure agent is on your login PATH."
        case .claude:
            "Install Claude Code (https://claude.com/claude-code), run claude once to sign in, or set its path in Settings."
        }
    }

    /// Model used when Settings leaves the field empty. Commit drafts are a small task,
    /// so Claude gets the fast, cheap tier instead of the account default.
    var defaultModel: String {
        switch self {
        case .cursor: "auto"
        case .claude: "haiku"
        }
    }

    var modelHint: String {
        switch self {
        case .cursor: "auto, composer-2.5, … (see agent models)"
        case .claude: "haiku, sonnet, or a full model id"
        }
    }

    /// Read-only, non-interactive invocation that prints only the reply text.
    func arguments(executable: String, model: String, prompt: String) -> [String] {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelArgs = ["--model", trimmed.isEmpty ? defaultModel : trimmed]
        switch self {
        case .cursor:
            // Ask mode is read-only: no git commit / write tools.
            // --trust skips the interactive workspace-trust prompt required in -p mode.
            return [executable, "-p", "--trust", "--mode", "ask", "--output-format", "text"] + modelArgs + [prompt]
        case .claude:
            // The prompt already carries the diff, so every tool and MCP server is off.
            // `--tools` is variadic: `--` ends it before the prompt.
            return [executable, "-p", "--output-format", "text", "--no-session-persistence", "--strict-mcp-config"]
                + modelArgs
                + ["--tools", "", "--", prompt]
        }
    }

    /// Well-known install locations checked after the login PATH.
    var fallbackLocations: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .cursor:
            return ["\(home)/.local/bin/agent"]
        case .claude:
            return ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude"]
        }
    }

    static func load(_ defaults: UserDefaults = .standard) -> CommitAgentProvider {
        defaults.string(forKey: defaultsKey).flatMap(CommitAgentProvider.init(rawValue:)) ?? fallback
    }
}

/// Saved commit-agent choice plus optional binary path and model per provider.
struct CommitAgentConfig: Equatable, Sendable {
    var provider: CommitAgentProvider
    var customPath: String
    /// Empty means `provider.defaultModel`.
    var model: String = ""

    static func pathKey(_ provider: CommitAgentProvider) -> String {
        "commitAgentPath.\(provider.rawValue)"
    }

    static func modelKey(_ provider: CommitAgentProvider) -> String {
        "commitAgentModel.\(provider.rawValue)"
    }

    static func load(_ defaults: UserDefaults = .standard) -> CommitAgentConfig {
        let provider = CommitAgentProvider.load(defaults)
        return CommitAgentConfig(
            provider: provider,
            customPath: defaults.string(forKey: pathKey(provider)) ?? "",
            model: defaults.string(forKey: modelKey(provider)) ?? ""
        )
    }

    /// Model actually passed to the CLI.
    var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: CommitAgentProvider.defaultsKey)
        Self.store(customPath, key: Self.pathKey(provider), defaults)
        Self.store(model, key: Self.modelKey(provider), defaults)
    }

    private static func store(_ value: String, key: String, _ defaults: UserDefaults) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }

    /// Custom path → login PATH → well-known install locations.
    func resolveExecutable(extraPath: String?) -> Result<String, Safety.Failure> {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: expanded) else {
                return .failure(.missingBinary(expanded, hint: "The path set in Settings is not an executable file."))
            }
            return .success(expanded)
        }
        if case .success(let resolved) = Safety.requireBinaryOnPath(provider.binaryName, extraPath: extraPath) {
            return .success(resolved)
        }
        if let found = provider.fallbackLocations.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return .success(found)
        }
        return .failure(.missingBinary(provider.binaryName, hint: provider.installHint))
    }
}
