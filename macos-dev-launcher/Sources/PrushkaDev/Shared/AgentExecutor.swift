import Foundation

@MainActor
enum AgentExecutor {
    static func run(
        _ command: AgentCommand,
        model: LauncherModel,
        audio: AudioQaStore
    ) async -> AgentHTTPResponse {
        guard let root = model.validatedRoot else {
            return AgentHTTPResponse.json(400, .object(["error": .string("Checkout is not available.")]))
        }
        switch command {
        case .catalog:
            return AgentHTTPResponse.json(200, catalog(model))
        case .services:
            return AgentHTTPResponse.json(200, .object(["units": .array(units(model))]))
        case .serviceLog(let id):
            model.refreshServiceLog(unitID: id)
            let text = model.serviceLog(for: id).consoleText
            return AgentHTTPResponse.json(200, .object([
                "id": .string(id),
                "text": .string(AgentText.tail(text)),
            ]))
        case .startUnit(let id):
            await model.start(unitID: id)
            return outcome(model, .object(["id": .string(id)]))
        case .stopUnit(let id, let confirmed):
            if model.unit(id: id)?.showsExternalBadge == true && !confirmed {
                return AgentHTTPResponse.json(400, .object(["error": .string("confirmed is required")]))
            }
            await model.stop(unitID: id, confirmed: confirmed)
            return outcome(model, .object(["id": .string(id)]))
        case .startDefault:
            await model.startDefault()
            return outcome(model, .object(["ok": .bool(model.actionError == nil)]))
        case .stopAll:
            await model.stopAll(confirmed: true)
            return outcome(model, .object(["ok": .bool(model.actionError == nil)]))
        case .checks:
            return AgentHTTPResponse.json(200, .object(["jobs": .array(QualityCatalog.jobs.map(checkJSON))]))
        case .check(let id):
            return checkState(model, id: id)
        case .runCheck(let id):
            guard let job = QualityCatalog.job(id: id) else {
                return AgentHTTPResponse.json(404, .object(["error": .string("Unknown check.")]))
            }
            await model.runQuality(job)
            await Task.yield()
            return checkState(model, id: id)
        case .cancelCheck(let id):
            model.cancelQuality(id)
            return AgentHTTPResponse.json(200, .object(["id": .string(id), "state": .string("cancel-requested")]))
        case .gitStatus:
            return AgentHTTPResponse.json(200, git(model))
        case .refreshGit:
            await model.refreshGitStatus()
            return AgentHTTPResponse.json(200, git(model))
        case .selectGitRepo(let id):
            await model.selectGitRepoAwaitingRefresh(id)
            return AgentHTTPResponse.json(200, git(model))
        case .stageGit(let all, let paths):
            if !all { model.gitSelectedPaths = Set(paths) }
            await model.stageGit(all: all)
            return outcome(model, git(model))
        case .unstageGit(let all, let paths):
            if !all { model.gitSelectedPaths = Set(paths) }
            await model.unstageGit(all: all)
            return outcome(model, git(model))
        case .setCommitMessage(let message):
            model.commitMessageDraft = message
            return AgentHTTPResponse.json(200, .object(["commitMessage": .string(message)]))
        case .generateCommitMessage:
            await model.generateCommitMessage()
            return outcome(model, .object(["commitMessage": .string(model.commitMessageDraft)]))
        case .commit(let message):
            if let message { model.commitMessageDraft = message }
            await model.commitWithDraft(confirmed: true)
            return outcome(model, git(model))
        case .push:
            await model.pushGit(confirmed: true)
            return outcome(model, git(model))
        case .tools:
            return AgentHTTPResponse.json(200, .object(["tools": .array(model.tools.map(toolJSON))]))
        case .toolOutput:
            return AgentHTTPResponse.json(200, toolResult(model))
        case .runTool(let id, let text, let flags):
            guard let tool = model.tools.first(where: { $0.id == id }) else {
                return AgentHTTPResponse.json(404, .object(["error": .string("Unknown tool.")]))
            }
            await model.run(tool: tool, text: text, flags: flags)
            await Task.yield()
            return outcome(model, toolResult(model))
        case .cancelTool:
            model.cancelTool()
            return AgentHTTPResponse.json(200, .object(["state": .string("cancel-requested")]))
        case .logs:
            return AgentHTTPResponse.json(200, .object(["units": .array(units(model))]))
        case .log(let id):
            model.selectLog(id)
            return AgentHTTPResponse.json(200, .object([
                "id": .string(id),
                "text": .string(AgentText.tail(model.logText)),
            ]))
        case .audioScenarios:
            audio.reload(root: root)
            let files = audio.scenarioFiles.map { url -> JSONValue in
                .object([
                    "name": .string(url.lastPathComponent),
                    "path": .string(url.path),
                ])
            }
            return AgentHTTPResponse.json(200, .object(["scenarios": .array(files)]))
        case .audioRuns:
            audio.reload(root: root)
            let runs = audio.runFiles.map { url -> JSONValue in
                .object([
                    "id": .string(url.deletingPathExtension().lastPathComponent),
                    "path": .string(url.path),
                ])
            }
            return AgentHTTPResponse.json(200, .object(["runs": .array(runs)]))
        case .audioLatest(let view):
            audio.reload(root: root)
            guard let report = audio.report, let url = audio.reportURL else {
                return AgentHTTPResponse.json(404, .object(["error": .string("No run yet.")]))
            }
            return audioReport(report, url: url, view: view, log: audio.log)
        case .audioRunFile(let id, let view):
            guard let url = runFile(root: root, id: id), let report = AudioQaDigest.load(url) else {
                return AgentHTTPResponse.json(404, .object(["error": .string("Run not found.")]))
            }
            return audioReport(report, url: url, view: view, log: "")
        case .audioRun(let scope, let suite, let scenario, let mode):
            audio.scope = scope
            if let suite { audio.selectedSuite = suite }
            if let scenario {
                guard let file = scenarioFile(root: root, raw: scenario) else {
                    return AgentHTTPResponse.json(400, .object(["error": .string("Scenario is outside the Audio QA catalog.")]))
                }
                audio.selectedScenario = file.path
            }
            await audio.run(root: root, extraPath: model.loginShellPath, mode: mode)
            audio.reload(root: root)
            guard let report = audio.report, let url = audio.reportURL else {
                return AgentHTTPResponse.json(500, .object([
                    "error": .string(audio.error ?? "Audio QA did not write a report."),
                    "log": .string(AgentText.tail(audio.log, max: 8_000)),
                ]))
            }
            return audioReport(report, url: url, view: "digest", log: audio.log)
        case .audioSynthesize(let scenario, let out):
            guard let file = scenarioFile(root: root, raw: scenario) else {
                return AgentHTTPResponse.json(400, .object(["error": .string("Scenario is outside the Audio QA catalog.")]))
            }
            let destination = wavDestination(root: root, raw: out)
            guard let destination else {
                return AgentHTTPResponse.json(400, .object(["error": .string("WAV output must stay under .audio-qa.")]))
            }
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            await audio.synthesize(
                root: root,
                extraPath: model.loginShellPath,
                scenario: file,
                out: destination
            )
            if let error = audio.error {
                return AgentHTTPResponse.json(500, .object(["error": .string(error)]))
            }
            return AgentHTTPResponse.json(200, .object(["wavPath": .string(destination.path)]))
        case .audioSaveRegression(let id):
            guard let scenario = audio.report?.scenarios.first(where: { $0.id == id }) else {
                return AgentHTTPResponse.json(404, .object(["error": .string("Scenario is not in the loaded report.")]))
            }
            await audio.saveRegression(root: root, extraPath: model.loginShellPath, scenario: scenario)
            return outcome(audio.error, .object(["id": .string(id)]))
        case .audioCancel:
            audio.cancel()
            return AgentHTTPResponse.json(200, .object(["state": .string("cancel-requested")]))
        case .control:
            return AgentHTTPResponse.json(500, .object(["error": .string("Control is served by the coordinator.")]))
        case .job, .jobs:
            return AgentHTTPResponse.json(404, .object(["error": .string("Job state is served by the coordinator.")]))
        }
    }

    private static func audioReport(
        _ report: AudioQaRunFile,
        url: URL,
        view: String,
        log: String
    ) -> AgentHTTPResponse {
        if view == "full", let data = try? Data(contentsOf: url) {
            return AgentHTTPResponse(status: 200, body: AudioQaDigest.attachingPath(data, path: url.path))
        }
        var digest = AudioQaDigest.make(report: report, reportPath: url.path)
        if case .object(var fields) = digest {
            fields["log"] = .string(AgentText.tail(log, max: 8_000))
            digest = .object(fields)
        }
        return AgentHTTPResponse.json(200, digest)
    }

    private static func catalog(_ model: LauncherModel) -> JSONValue {
        .object([
            "sections": .array(["services", "checks", "git", "tools", "logs", "audioQa"].map(JSONValue.string)),
            "services": .array(Safety.knownUnitIDs.sorted().map(JSONValue.string)),
            "checks": .array(QualityCatalog.jobs.map { .string($0.id) }),
            "tools": .array(model.tools.map { .string($0.id) }),
            "gitRepos": .array(GitCatalog.repos.map { .string($0.id) }),
            "audioQaSuites": .array(AudioQaCatalog.suites.map { .string($0.id) }),
            "listening": .bool(true),
        ])
    }

    private static func units(_ model: LauncherModel) -> [JSONValue] {
        let source = model.units.isEmpty
            ? Safety.knownUnitIDs.sorted().map { id in
                UnitStatus(
                    id: id,
                    label: model.label(for: id),
                    kind: "",
                    state: "unknown",
                    source: "",
                    pid: nil,
                    pids: [],
                    health: "unknown",
                    url: nil,
                    logFile: nil
                )
            }
            : model.units
        return source.map { unit in
            .object([
                "id": .string(unit.id),
                "label": .string(unit.label),
                "state": .string(unit.state),
                "health": .string(unit.health),
                "url": unit.url.map(JSONValue.string) ?? .null,
                "busy": .bool(model.isBusy(unit.id)),
            ])
        }
    }

    private static func checkJSON(_ job: QualityJob) -> JSONValue {
        .object([
            "id": .string(job.id),
            "title": .string(job.title),
            "summary": .string(job.summary),
            "group": .string(job.group.rawValue),
        ])
    }

    private static func checkState(_ model: LauncherModel, id: String) -> AgentHTTPResponse {
        let state = model.qualityRun(for: id)
        return AgentHTTPResponse.json(200, .object([
            "id": .string(id),
            "outcome": .string(state.outcome.rawValue),
            "exitCode": state.exitCode.map { .number(Double($0)) } ?? .null,
            "lastLine": .string(state.lastLine),
            "output": .string(AgentText.tail(state.consoleText)),
            "error": model.actionError.map(JSONValue.string) ?? .null,
        ]))
    }

    private static func toolJSON(_ tool: RegistryTool) -> JSONValue {
        .object([
            "id": .string(tool.id),
            "label": .string(tool.label),
            "args": .array(tool.args.map { arg in
                .object([
                    "name": .string(arg.name),
                    "flag": .string(arg.flag),
                    "type": .string(arg.type),
                    "required": .bool(arg.required),
                ])
            }),
        ])
    }

    private static func toolResult(_ model: LauncherModel) -> JSONValue {
        .object([
            "title": .string(model.toolOutputTitle),
            "output": .string(AgentText.tail(model.toolOutput)),
            "error": model.actionError.map(JSONValue.string) ?? .null,
        ])
    }

    private static func git(_ model: LauncherModel) -> JSONValue {
        let entries = model.gitEntries.prefix(200).map { entry -> JSONValue in
            .object([
                "path": .string(entry.path),
                "kind": .string(entry.kind.rawValue),
                "status": .string(entry.statusLabel),
            ])
        }
        return .object([
            "repo": .string(model.selectedGitRepoID),
            "branch": .string(model.gitBranch),
            "upstream": model.gitUpstream.map(JSONValue.string) ?? .null,
            "ahead": .number(Double(model.gitAhead)),
            "behind": .number(Double(model.gitBehind)),
            "canPush": .bool(model.canPushGit),
            "busy": .bool(model.gitBusy),
            "commitMessage": .string(model.commitMessageDraft),
            "error": (model.gitStatusError ?? model.actionError).map(JSONValue.string) ?? .null,
            "truncated": .bool(model.gitEntries.count > 200),
            "entries": .array(Array(entries)),
            "unpushed": .array(model.gitUnpushedCommits.map { commit in
                .object([
                    "hash": .string(commit.hash),
                    "subject": .string(commit.subject),
                ])
            }),
        ])
    }

    private static func outcome(_ model: LauncherModel, _ value: JSONValue) -> AgentHTTPResponse {
        outcome(model.actionError, value)
    }

    private static func outcome(_ error: String?, _ value: JSONValue) -> AgentHTTPResponse {
        guard let error else { return AgentHTTPResponse.json(200, value) }
        return AgentHTTPResponse.json(500, .object([
            "error": .string(error),
            "result": value,
        ]))
    }

    private static func runFile(root: URL, id: String) -> URL? {
        guard !id.isEmpty, !id.contains("/"), !id.contains(".."), id != "latest" else { return nil }
        let directory = root.appendingPathComponent("front/apps/web/.audio-qa/runs").standardizedFileURL
        let url = directory.appendingPathComponent("\(id).json").standardizedFileURL
        guard url.path.hasPrefix(directory.path + "/") else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func scenarioFile(root: URL, raw: String) -> URL? {
        let candidate = raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw)
            : root.appendingPathComponent(raw)
        let url = candidate.standardizedFileURL
        guard url.pathExtension == "json" else { return nil }
        let allowed = [
            root.appendingPathComponent("front/apps/web/src/features/audio-qa/scenarios"),
            root.appendingPathComponent("front/apps/web/.audio-qa/scenarios"),
        ].map(\.standardizedFileURL)
        guard allowed.contains(where: { url.path == $0.path || url.path.hasPrefix($0.path + "/") }) else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private static func wavDestination(root: URL, raw: String?) -> URL? {
        let directory = root.appendingPathComponent("front/apps/web/.audio-qa").standardizedFileURL
        let url = (raw.map { value -> URL in
            value.hasPrefix("/") ? URL(fileURLWithPath: value) : root.appendingPathComponent(value)
        } ?? directory.appendingPathComponent("preview.wav")).standardizedFileURL
        guard url.pathExtension == "wav" else { return nil }
        guard url.path == directory.path || url.path.hasPrefix(directory.path + "/") else { return nil }
        return url
    }
}
