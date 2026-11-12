import Foundation

struct AgentCursor: Equatable, Identifiable {
    var token: Int
    var section: AppSection
    var action: String
    var targetID: String

    var id: Int { token }

    var line: String { "\(section.title) · \(action)" }
}

/// Moves the launcher to the section and control an agent command is using.
@MainActor
enum AgentPresence {
    static func apply(
        _ command: AgentCommand,
        model: LauncherModel,
        audio: AudioQaStore,
        token: Int
    ) -> AgentCursor {
        let cursor = cursor(for: command, model: model, audio: audio, token: token)
        model.section = cursor.section
        return cursor
    }

    static func results(token: Int) -> AgentCursor {
        AgentCursor(
            token: token,
            section: .audioQa,
            action: "Opened the report",
            targetID: "audio-results"
        )
    }

    private static func cursor(
        for command: AgentCommand,
        model: LauncherModel,
        audio: AudioQaStore,
        token: Int
    ) -> AgentCursor {
        switch command {
        case .catalog:
            return stay(model, token: token, action: "Read catalog", targetID: "catalog")
        case .services:
            return go(.services, token: token, action: "Services", targetID: "services")
        case .serviceLog(let id):
            model.showService(unitID: id)
            return go(.services, token: token, action: "Open \(unitLabel(id)) log", targetID: id)
        case .startUnit(let id):
            model.showService(unitID: id)
            return go(.services, token: token, action: "Start \(unitLabel(id))", targetID: id)
        case .stopUnit(let id, _):
            model.showService(unitID: id)
            return go(.services, token: token, action: "Stop \(unitLabel(id))", targetID: id)
        case .startDefault:
            return go(.services, token: token, action: "Start default", targetID: "services-start-default")
        case .stopAll:
            return go(.services, token: token, action: "Stop all", targetID: "services-stop-all")
        case .checks:
            return go(.checks, token: token, action: "Checks", targetID: "checks")
        case .check(let id):
            model.showCheck(id: id)
            return go(.checks, token: token, action: "Open \(checkLabel(id))", targetID: id)
        case .runCheck(let id):
            model.showCheck(id: id)
            return go(.checks, token: token, action: "Run \(checkLabel(id))", targetID: id)
        case .cancelCheck(let id):
            model.showCheck(id: id)
            return go(.checks, token: token, action: "Stop \(checkLabel(id))", targetID: id)
        case .gitStatus:
            return go(.git, token: token, action: "Git status", targetID: "git-refresh")
        case .refreshGit:
            return go(.git, token: token, action: "Refresh", targetID: "git-refresh")
        case .selectGitRepo(let id):
            return go(.git, token: token, action: "Select \(repoLabel(id))", targetID: "git-repo-\(id)")
        case .stageGit(let all, let paths):
            if !all { model.gitSelectedPaths = Set(paths) }
            return go(.git, token: token, action: all ? "Stage all" : "Stage \(paths.count) files", targetID: all ? "git-stage-all" : "git-stage")
        case .unstageGit(let all, let paths):
            if !all { model.gitSelectedPaths = Set(paths) }
            return go(.git, token: token, action: all ? "Unstage all" : "Unstage \(paths.count) files", targetID: all ? "git-unstage-all" : "git-unstage")
        case .setCommitMessage(let message):
            model.commitMessageDraft = message
            return go(.git, token: token, action: "Set commit message", targetID: "git-message")
        case .generateCommitMessage:
            return go(.git, token: token, action: "Generate commit message", targetID: "git-generate")
        case .commit(let message):
            if let message { model.commitMessageDraft = message }
            return go(.git, token: token, action: "Commit", targetID: "git-commit")
        case .push:
            return go(.git, token: token, action: "Push", targetID: "git-push")
        case .tools:
            return go(.tools, token: token, action: "Tools", targetID: "tools")
        case .toolOutput:
            return go(.tools, token: token, action: "Tool output", targetID: "tool-output")
        case .runTool(let id, let text, let flags):
            model.selectedToolID = id
            model.agentToolText = text
            model.agentToolFlags = flags
            model.agentToolRevision += 1
            return go(.tools, token: token, action: "Run \(toolLabel(id, model: model))", targetID: "tool-run")
        case .cancelTool:
            return go(.tools, token: token, action: "Stop tool", targetID: "tool-stop")
        case .logs:
            return go(.logs, token: token, action: "Logs", targetID: model.selectedLogID)
        case .log(let id):
            model.selectLog(id)
            return go(.logs, token: token, action: unitLabel(id), targetID: id)
        case .audioScenarios:
            revealAudio(audio, root: model.validatedRoot, screen: .suites)
            return go(.audioQa, token: token, action: "Scenarios", targetID: "audio-suites")
        case .audioRuns, .audioLatest, .audioRunFile:
            revealAudio(audio, root: model.validatedRoot, screen: .results)
            return go(.audioQa, token: token, action: "Open run", targetID: "audio-results")
        case .audioRun(let scope, let suite, let scenario, let mode):
            revealAudio(audio, root: model.validatedRoot, screen: .runner)
            audio.scope = scope
            if let suite { audio.selectedSuite = suite }
            return go(.audioQa, token: token, action: runLabel(scope: scope, suite: suite, scenario: scenario, mode: mode), targetID: "audio-run")
        case .audioSynthesize:
            revealAudio(audio, root: model.validatedRoot, screen: .builder)
            return go(.audioQa, token: token, action: "Synthesize", targetID: "audio-builder")
        case .audioSaveRegression(let id):
            revealAudio(audio, root: model.validatedRoot, screen: .results)
            return go(.audioQa, token: token, action: "Save regression \(id)", targetID: "audio-save-\(id)")
        case .audioCancel:
            revealAudio(audio, root: model.validatedRoot, screen: .runner)
            return go(.audioQa, token: token, action: "Cancel", targetID: "audio-cancel")
        case .control, .job, .jobs:
            return stay(model, token: token, action: "Agent", targetID: "")
        }
    }

    private static func revealAudio(_ audio: AudioQaStore, root: URL?, screen: AudioQaScreen) {
        if let root { audio.reload(root: root) }
        audio.screen = screen
    }

    private static func go(
        _ section: AppSection,
        token: Int,
        action: String,
        targetID: String
    ) -> AgentCursor {
        AgentCursor(token: token, section: section, action: action, targetID: targetID)
    }

    private static func stay(
        _ model: LauncherModel,
        token: Int,
        action: String,
        targetID: String
    ) -> AgentCursor {
        AgentCursor(token: token, section: model.section, action: action, targetID: targetID)
    }

    private static func unitLabel(_ id: String) -> String {
        let chip = UnitFace.chip(for: id)
        return chip.isEmpty ? UnitFace.title(for: id) : "\(UnitFace.title(for: id)) \(chip)"
    }

    private static func checkLabel(_ id: String) -> String {
        guard let job = QualityCatalog.job(id: id) else { return id }
        return "\(job.title) \(job.chip)"
    }

    private static func repoLabel(_ id: String) -> String {
        GitCatalog.repo(id: id)?.label ?? id
    }

    private static func toolLabel(_ id: String, model: LauncherModel) -> String {
        model.tools.first { $0.id == id }?.shortTitle ?? id
    }

    private static func runLabel(
        scope: String,
        suite: String?,
        scenario: String?,
        mode: String?
    ) -> String {
        let base: String
        switch scope {
        case "all":
            base = "Run all"
        case "scenario":
            let name = scenario.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "scenario"
            base = "Run \(name)"
        default:
            let title = AudioQaCatalog.suites.first { $0.id == suite }?.title ?? (suite ?? "suite")
            base = "Run \(title)"
        }
        guard let mode, mode == "realtime" || mode == "direct" else { return base }
        return "\(base) · \(mode)"
    }
}
