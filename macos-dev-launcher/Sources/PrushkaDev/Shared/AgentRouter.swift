import Foundation

enum AgentDecision: Equatable, Sendable {
    case unauthorized
    case notFound
    case badRequest(String)
    case command(AgentCommand)
}

enum AgentCommand: Equatable, Sendable {
    case catalog
    case services
    case serviceLog(id: String)
    case startUnit(id: String)
    case stopUnit(id: String, confirmed: Bool)
    case startDefault
    case stopAll
    case checks
    case check(id: String)
    case runCheck(id: String)
    case cancelCheck(id: String)
    case gitStatus
    case refreshGit
    case selectGitRepo(id: String)
    case stageGit(all: Bool, paths: [String])
    case unstageGit(all: Bool, paths: [String])
    case setCommitMessage(String)
    case generateCommitMessage
    case commit(message: String?)
    case push
    case tools
    case toolOutput
    case runTool(id: String, text: [String: String], flags: [String: Bool])
    case cancelTool
    case logs
    case log(id: String)
    case audioScenarios
    case audioRuns
    case audioLatest(view: String)
    case audioRunFile(id: String, view: String)
    case audioRun(scope: String, suite: String?, scenario: String?, mode: String?)
    case audioSynthesize(scenario: String, out: String?)
    case audioSaveRegression(id: String)
    case audioCancel
    case control(active: Bool)
    case job(id: String)
    case jobs

    var startsJob: Bool {
        switch self {
        case .startUnit, .stopUnit, .startDefault, .stopAll,
             .runCheck, .refreshGit, .selectGitRepo, .stageGit, .unstageGit,
             .generateCommitMessage, .commit, .push, .runTool,
             .audioRun, .audioSynthesize, .audioSaveRegression:
            return true
        default:
            return false
        }
    }

    var kind: String {
        switch self {
        case .startUnit(let id): "service.start.\(id)"
        case .stopUnit(let id, _): "service.stop.\(id)"
        case .startDefault: "service.start-default"
        case .stopAll: "service.stop-all"
        case .runCheck(let id): "check.\(id)"
        case .refreshGit: "git.refresh"
        case .selectGitRepo(let id): "git.select.\(id)"
        case .stageGit: "git.stage"
        case .unstageGit: "git.unstage"
        case .generateCommitMessage: "git.generate-message"
        case .commit: "git.commit"
        case .push: "git.push"
        case .runTool(let id, _, _): "tool.\(id)"
        case .audioRun: "audio-qa.run"
        case .audioSynthesize: "audio-qa.synthesize"
        case .audioSaveRegression: "audio-qa.save-regression"
        default: "query"
        }
    }
}

enum AgentRouter {
    private static let blocked: Set<String> = ["settings", "shell", "rebuild", "repo-root"]

    static func route(_ request: AgentRequest, token: String) -> AgentDecision {
        guard authorize(request, token: token) else { return .unauthorized }
        if request.path.contains("..") { return .notFound }
        let parts = request.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if parts.contains(where: { blocked.contains($0) }) { return .notFound }
        guard parts.first == "v1" else { return .notFound }
        return dispatch(method: request.method, parts: Array(parts.dropFirst()), request: request)
    }

    private static func authorize(_ request: AgentRequest, token: String) -> Bool {
        guard !token.isEmpty, let header = request.headers["authorization"] else { return false }
        let expected = Array("Bearer \(token)".utf8)
        let actual = Array(header.utf8)
        guard expected.count == actual.count else { return false }
        return zip(expected, actual).allSatisfy(==)
    }

    private static func dispatch(method: String, parts: [String], request: AgentRequest) -> AgentDecision {
        if method == "GET" && parts == ["catalog"] { return .command(.catalog) }
        if method == "GET" && parts == ["services"] { return .command(.services) }
        if method == "POST" && parts == ["services", "start-default"] { return .command(.startDefault) }
        if method == "POST" && parts == ["services", "stop-all"] { return confirmed(request) { .stopAll } }
        if method == "GET", parts.count == 3, parts[0] == "services", parts[2] == "log" {
            let id = parts[1]
            return knownUnit(id) { .serviceLog(id: id) }
        }
        if method == "POST", parts.count == 3, parts[0] == "services", parts[2] == "start" {
            let id = parts[1]
            return knownUnit(id) { .startUnit(id: id) }
        }
        if method == "POST", parts.count == 3, parts[0] == "services", parts[2] == "stop" {
            let id = parts[1]
            return knownUnit(id) {
                .stopUnit(id: id, confirmed: flag(request, name: "confirmed") == true)
            }
        }
        if method == "GET" && parts == ["checks"] { return .command(.checks) }
        if method == "GET", parts.count == 2, parts[0] == "checks" {
            let id = parts[1]
            return knownCheck(id) { .check(id: id) }
        }
        if method == "POST", parts.count == 3, parts[0] == "checks", parts[2] == "run" {
            let id = parts[1]
            return knownCheck(id) { .runCheck(id: id) }
        }
        if method == "POST", parts.count == 3, parts[0] == "checks", parts[2] == "cancel" {
            let id = parts[1]
            return knownCheck(id) { .cancelCheck(id: id) }
        }
        if method == "GET" && parts == ["git"] { return .command(.gitStatus) }
        if method == "POST" && parts == ["git", "refresh"] { return .command(.refreshGit) }
        if method == "POST" && parts == ["git", "select"] { return gitSelect(request) }
        if method == "POST" && parts == ["git", "stage"] {
            return gitPaths(request) { .stageGit(all: $0, paths: $1) }
        }
        if method == "POST" && parts == ["git", "unstage"] {
            return gitPaths(request) { .unstageGit(all: $0, paths: $1) }
        }
        if method == "POST" && parts == ["git", "message"] { return gitMessage(request) }
        if method == "POST" && parts == ["git", "generate-message"] { return .command(.generateCommitMessage) }
        if method == "POST" && parts == ["git", "commit"] {
            return confirmed(request) { .commit(message: optionalString(request, name: "message")) }
        }
        if method == "POST" && parts == ["git", "push"] { return confirmed(request) { .push } }
        if method == "GET" && parts == ["tools"] { return .command(.tools) }
        if method == "GET" && parts == ["tools", "output"] { return .command(.toolOutput) }
        if method == "POST" && parts == ["tools", "cancel"] { return .command(.cancelTool) }
        if method == "POST", parts.count == 3, parts[0] == "tools", parts[2] == "run" {
            return toolRun(id: parts[1], request: request)
        }
        if method == "GET" && parts == ["logs"] { return .command(.logs) }
        if method == "GET", parts.count == 2, parts[0] == "logs" {
            let id = parts[1]
            return knownUnit(id) { .log(id: id) }
        }
        if method == "GET" && parts == ["audio-qa", "scenarios"] { return .command(.audioScenarios) }
        if method == "GET" && parts == ["audio-qa", "runs"] { return .command(.audioRuns) }
        if method == "GET" && parts == ["audio-qa", "runs", "latest"] {
            return audioView(request) { .audioLatest(view: $0) }
        }
        if method == "GET", parts.count == 3, parts[0] == "audio-qa", parts[1] == "runs" {
            let id = parts[2]
            return audioView(request) { .audioRunFile(id: id, view: $0) }
        }
        if method == "POST" && parts == ["audio-qa", "run"] { return audioRun(request) }
        if method == "POST" && parts == ["audio-qa", "synthesize"] { return audioSynthesize(request) }
        if method == "POST" && parts == ["audio-qa", "save-regression"] {
            return requiredString(request, name: "id") { .audioSaveRegression(id: $0) }
        }
        if method == "POST" && parts == ["audio-qa", "cancel"] { return .command(.audioCancel) }
        if method == "POST" && parts == ["control"] { return control(request) }
        if method == "GET" && parts == ["jobs"] { return .command(.jobs) }
        if method == "GET", parts.count == 2, parts[0] == "jobs" {
            return .command(.job(id: parts[1]))
        }
        return .notFound
    }

    private static func control(_ request: AgentRequest) -> AgentDecision {
        guard let active = flag(request, name: "active") else {
            return .badRequest("active is required")
        }
        return .command(.control(active: active))
    }

    private static func knownUnit(_ id: String, _ command: () -> AgentCommand) -> AgentDecision {
        Safety.knownUnitIDs.contains(id) ? .command(command()) : .notFound
    }

    private static func knownCheck(_ id: String, _ command: () -> AgentCommand) -> AgentDecision {
        QualityCatalog.job(id: id) == nil ? .notFound : .command(command())
    }

    private static func confirmed(_ request: AgentRequest, _ command: () -> AgentCommand) -> AgentDecision {
        guard flag(request, name: "confirmed") == true else {
            return .badRequest("confirmed is required")
        }
        return .command(command())
    }

    private static func gitSelect(_ request: AgentRequest) -> AgentDecision {
        guard let body = object(request) else { return .badRequest("JSON object required") }
        guard let id = body["id"] as? String, GitCatalog.repo(id: id) != nil else {
            return .notFound
        }
        return .command(.selectGitRepo(id: id))
    }

    private static func gitPaths(
        _ request: AgentRequest,
        _ command: (Bool, [String]) -> AgentCommand
    ) -> AgentDecision {
        guard let body = object(request) else { return .badRequest("JSON object required") }
        let all = body["all"] as? Bool ?? false
        let paths = stringList(body["paths"]) ?? []
        if !all && paths.isEmpty {
            return .badRequest("paths or all is required")
        }
        return .command(command(all, paths))
    }

    private static func gitMessage(_ request: AgentRequest) -> AgentDecision {
        guard let body = object(request) else { return .badRequest("JSON object required") }
        guard let message = body["message"] as? String,
              !message.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            return .badRequest("message is required")
        }
        return .command(.setCommitMessage(message))
    }

    private static func toolRun(id: String, request: AgentRequest) -> AgentDecision {
        guard Safety.knownToolIDs.contains(id) else { return .notFound }
        guard let body = object(request) else { return .badRequest("JSON object required") }
        let text = stringMap(body["text"]) ?? [:]
        let flags = boolMap(body["flags"]) ?? [:]
        if body["text"] != nil && stringMap(body["text"]) == nil {
            return .badRequest("text must be an object of strings")
        }
        if body["flags"] != nil && boolMap(body["flags"]) == nil {
            return .badRequest("flags must be an object of booleans")
        }
        return .command(.runTool(id: id, text: text, flags: flags))
    }

    private static func audioView(_ request: AgentRequest, _ command: (String) -> AgentCommand) -> AgentDecision {
        let view = request.query["view"] ?? "digest"
        guard view == "digest" || view == "full" else {
            return .badRequest("view must be digest or full")
        }
        return .command(command(view))
    }

    private static func audioRun(_ request: AgentRequest) -> AgentDecision {
        guard let body = object(request) else { return .badRequest("JSON object required") }
        guard let scope = body["scope"] as? String, ["suite", "scenario", "all"].contains(scope) else {
            return .badRequest("scope must be suite, scenario, or all")
        }
        let suite = body["suite"] as? String
        let scenario = body["scenario"] as? String
        if scope == "suite" && (suite ?? "").isEmpty {
            return .badRequest("suite is required")
        }
        if scope == "scenario" && (scenario ?? "").isEmpty {
            return .badRequest("scenario is required")
        }
        if let suite, !AudioQaCatalog.suites.contains(where: { $0.id == suite }) {
            return .notFound
        }
        let mode = body["mode"] as? String
        if let mode, mode != "direct" && mode != "realtime" {
            return .badRequest("mode must be direct or realtime")
        }
        return .command(.audioRun(scope: scope, suite: suite, scenario: scenario, mode: mode))
    }

    private static func audioSynthesize(_ request: AgentRequest) -> AgentDecision {
        guard let body = object(request) else { return .badRequest("JSON object required") }
        guard let scenario = body["scenario"] as? String, !scenario.isEmpty else {
            return .badRequest("scenario is required")
        }
        let out = body["out"] as? String
        return .command(.audioSynthesize(scenario: scenario, out: out))
    }

    private static func requiredString(
        _ request: AgentRequest,
        name: String,
        _ command: (String) -> AgentCommand
    ) -> AgentDecision {
        guard let body = object(request) else { return .badRequest("JSON object required") }
        guard let value = body[name] as? String, !value.isEmpty else {
            return .badRequest("\(name) is required")
        }
        return .command(command(value))
    }

    private static func optionalString(_ request: AgentRequest, name: String) -> String? {
        guard let body = object(request) else { return nil }
        return body[name] as? String
    }

    private static func flag(_ request: AgentRequest, name: String) -> Bool? {
        guard let body = object(request) else { return nil }
        return body[name] as? Bool
    }

    private static func object(_ request: AgentRequest) -> [String: Any]? {
        if request.body.isEmpty { return [:] }
        return try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let values = value as? [Any] else { return nil }
        var result: [String] = []
        for item in values {
            guard let text = item as? String else { return nil }
            result.append(text)
        }
        return result
    }

    private static func stringMap(_ value: Any?) -> [String: String]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, item) in object {
            guard let text = item as? String else { return nil }
            result[key] = text
        }
        return result
    }

    private static func boolMap(_ value: Any?) -> [String: Bool]? {
        guard let object = value as? [String: Any] else { return nil }
        var result: [String: Bool] = [:]
        for (key, item) in object {
            guard let flag = item as? Bool else { return nil }
            result[key] = flag
        }
        return result
    }
}
