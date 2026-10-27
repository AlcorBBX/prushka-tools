import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class LauncherModel {
    public init() {}

    var section: AppSection = .services
    var repoRoot = ""
    var detectedRoot = ""
    var units: [UnitStatus] = []
    var registry: RegistryFile?
    var checkedAt = ""
    var statusError: String?
    var actionError: String?
    var busyIDs: Set<String> = []
    var selectedToolID = "tab-source-fetch"
    var toolOutput = ""
    var toolOutputTitle = ""
    var selectedLogID = "web-dev"
    var logText = ""
    var expandedQualityJobID: String?
    var qualityRuns: [String: QualityRunState] = [:]
    var expandedServiceFamilyID: String?
    var serviceLogs: [String: ServiceLogState] = [:]

    private var didBoot = false
    private var loginPath = ""
    private var pollTask: Task<Void, Never>?
    private var serviceLogPollTask: Task<Void, Never>?
    private var statusChain: Task<Void, Never>?
    private var activeProcess: ManagedProcess?

    var rootIsValid: Bool {
        RepoRoot.isRepo(repoRoot)
    }

    var validatedRoot: URL? {
        if case .success(let url) = Safety.validateRepo(repoRoot) {
            return url
        }
        return nil
    }

    var tools: [RegistryTool] {
        (registry?.tools ?? []).filter { Safety.knownToolIDs.contains($0.id) }
    }

    var selectedTool: RegistryTool? {
        tools.first { $0.id == selectedToolID } ?? tools.first
    }

    var checkedLabel: String {
        guard !checkedAt.isEmpty else { return "Waiting for status" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: checkedAt) else { return checkedAt }
        return date.formatted(date: .omitted, time: .standard)
    }

    public func bootstrap() async {
        guard !didBoot else { return }
        didBoot = true
        detectedRoot = RepoRoot.resolve(ignoringSaved: true)
        repoRoot = RepoRoot.resolve()
        loginPath = await ProcessRunner.captureLoginPath()
        await reloadRegistry()
        await refreshStatus()
        startPolling()
    }

    func unit(id: String) -> UnitStatus? {
        units.first { $0.id == id }
    }

    func label(for id: String) -> String {
        unit(id: id)?.label ?? registry?.units.first { $0.id == id }?.label ?? id
    }

    func isBusy(_ id: String) -> Bool {
        busyIDs.contains(id) || busyIDs.contains("bundle")
    }

    func setRepoRoot(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        switch Safety.validateRepo(trimmed) {
        case .success(let url):
            UserDefaults.standard.set(url.path, forKey: RepoRoot.defaultsKey)
            repoRoot = url.path
            actionError = nil
            Task { await reloadFromDisk() }
        case .failure(let error):
            actionError = error.localizedDescription
        }
    }

    func useDetectedRoot() {
        UserDefaults.standard.removeObject(forKey: RepoRoot.defaultsKey)
        detectedRoot = RepoRoot.resolve(ignoringSaved: true)
        if RepoRoot.isRepo(detectedRoot) {
            repoRoot = detectedRoot
            actionError = nil
            Task { await reloadFromDisk() }
        } else {
            actionError = Safety.Failure.invalidRepo.localizedDescription
        }
    }

    func refreshStatus() async {
        let previous = statusChain
        let task = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self.loadStatus()
        }
        statusChain = task
        await task.value
    }

    func start(unitID: String) async {
        switch Safety.validateUnitID(unitID) {
        case .failure(let error):
            actionError = error.localizedDescription
        case .success(let id):
            await runScript(name: "up.sh", arguments: [id, "--bg"], busy: id)
        }
    }

    func stop(unitID: String) async {
        switch Safety.validateUnitID(unitID) {
        case .failure(let error):
            actionError = error.localizedDescription
        case .success(let id):
            if unit(id: id)?.showsExternalBadge == true {
                let ok = Confirm.ask(
                    title: "Stop external process?",
                    message: "\(UnitFace.title(for: id)) was not started by Prushka L. Stopping it will terminate whatever is on that port.",
                    confirm: "Stop",
                    style: .warning
                )
                guard ok else { return }
            }
            await runScript(name: "down.sh", arguments: [id], busy: id)
        }
    }

    func startDefault() async {
        await runScript(name: "up.sh", arguments: ["dev", "all"], busy: "bundle")
    }

    func stopAll() async {
        let ok = Confirm.ask(
            title: "Stop all services?",
            message: "This stops every known Prushka unit, including processes started outside the launcher if they match the usual ports.",
            confirm: "Stop all",
            style: .warning
        )
        guard ok else { return }
        await runScript(name: "down.sh", arguments: [], busy: "bundle")
    }

    func openTarget(for id: String) -> String? {
        if let openURL = registry?.units.first(where: { $0.id == id })?.openUrl {
            return openURL
        }
        return unit(id: id)?.url
    }

    func open(urlString: String?) {
        guard let urlString else { return }
        switch Safety.openableURL(urlString) {
        case .success(let url):
            NSWorkspace.shared.open(url)
        case .failure(let error):
            actionError = error.localizedDescription
        }
    }

    func selectLog(_ id: String) {
        if case .success = Safety.validateUnitID(id) {
            selectedLogID = id
            reloadLog()
        }
    }

    func serviceLog(for unitID: String) -> ServiceLogState {
        if let existing = serviceLogs[unitID] {
            return existing
        }
        let created = ServiceLogState()
        serviceLogs[unitID] = created
        return created
    }

    func toggleServiceExpansion(_ familyID: String) {
        if expandedServiceFamilyID == familyID {
            expandedServiceFamilyID = nil
            stopServiceLogPolling()
        } else {
            expandedServiceFamilyID = familyID
            startServiceLogPolling()
        }
    }

    func refreshServiceLog(unitID: String) {
        guard let root = validatedRoot else {
            serviceLog(for: unitID).clear()
            return
        }
        let preferred = unit(id: unitID)?.logFile
        switch Safety.logFileURL(unitID: unitID, root: root, preferred: preferred) {
        case .success(let url):
            serviceLog(for: unitID).applyFileTail(LogTail.read(path: url.path))
        case .failure:
            serviceLog(for: unitID).clear()
        }
    }

    func run(tool: RegistryTool, text: [String: String], flags: [String: Bool]) async {
        guard let root = validatedRoot else {
            actionError = "Choose the Prushka checkout in Settings."
            return
        }
        let busy = "tool:\(tool.id)"
        guard !busyIDs.contains(busy) else { return }

        let prepared: (command: [String], cwd: URL)
        switch Safety.validateTool(tool, root: root) {
        case .failure(let error):
            actionError = error.localizedDescription
            return
        case .success(let value):
            prepared = value
        }

        var arguments = prepared.command
        for arg in tool.args {
            if arg.type == "boolean" {
                if flags[arg.name] == true {
                    arguments.append(arg.flag)
                }
                continue
            }
            let raw = text[arg.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty {
                if arg.required {
                    actionError = "\(tool.label) needs \(arg.name)."
                    return
                }
                continue
            }
            switch Safety.sanitizeToolValue(raw, type: arg.type) {
            case .failure(let error):
                actionError = error.localizedDescription
                return
            case .success(let value):
                arguments.append(arg.flag)
                arguments.append(value)
            }
        }

        busyIDs.insert(busy)
        actionError = nil
        toolOutput = ""
        toolOutputTitle = tool.label
        let output = await ProcessRunner.run(
            arguments: arguments,
            cwd: prepared.cwd,
            extraPath: loginPath,
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    self?.appendToolOutput(chunk)
                }
            },
            onStart: { [weak self] process in
                Task { @MainActor in
                    self?.activeProcess = process
                }
            }
        )
        busyIDs.remove(busy)
        activeProcess = nil
        if output.cancelled {
            appendToolOutput("\nStopped.\n")
            return
        }
        if output.code != 0 {
            actionError = output.combined.isEmpty
                ? "\(tool.label) failed (\(output.code))"
                : nil
            if toolOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                toolOutput = output.combined
            }
        }
    }

    func cancelTool() {
        activeProcess?.terminate()
    }

    func toolIsRunning(_ id: String) -> Bool {
        busyIDs.contains("tool:\(id)")
    }

    func qualityRun(for id: String) -> QualityRunState {
        if let existing = qualityRuns[id] {
            return existing
        }
        let created = QualityRunState()
        qualityRuns[id] = created
        return created
    }

    func toggleQualityExpansion(_ id: String) {
        if expandedQualityJobID == id {
            expandedQualityJobID = nil
        } else {
            expandedQualityJobID = id
        }
    }

    func runQuality(_ job: QualityJob) async {
        guard let root = validatedRoot else {
            actionError = "Choose the Prushka checkout in Settings."
            return
        }
        let busy = "quality:\(job.id)"
        guard !busyIDs.contains(busy) else { return }

        let prepared: (command: [String], cwd: URL)
        switch Safety.validateQualityJob(job, root: root) {
        case .failure(let error):
            actionError = error.localizedDescription
            return
        case .success(let value):
            prepared = value
        }

        let state = qualityRun(for: job.id)
        if state.isRunning {
            return
        }
        state.resetForRun()
        busyIDs.insert(busy)
        actionError = nil

        let output = await ProcessRunner.run(
            arguments: prepared.command,
            cwd: prepared.cwd,
            extraPath: loginPath,
            coalesce: .milliseconds(120),
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    self?.qualityRun(for: job.id).append(chunk)
                }
            },
            onStart: { [weak self] process in
                Task { @MainActor in
                    guard let self else { return }
                    // Resolve once up front so later coalesced chunks don't recreate dictionary entries.
                    self.qualityRun(for: job.id).process = process
                }
            }
        )

        busyIDs.remove(busy)
        state.process = nil
        state.exitCode = output.code
        if output.cancelled {
            state.outcome = .cancelled
            state.append("\nCancelled.\n")
        } else if output.code == 0 {
            state.outcome = .succeeded
            if state.lastLine.isEmpty || state.lastLine == "Starting…" {
                state.lastLine = "Finished successfully"
            }
        } else {
            state.outcome = .failed
            if state.consoleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.append(output.combined.isEmpty ? "Failed (\(output.code))\n" : output.combined + "\n")
            }
            if state.lastLine.isEmpty || state.lastLine == "Starting…" {
                state.lastLine = "Failed (\(output.code))"
            }
        }
    }

    func cancelQuality(_ id: String) {
        qualityRun(for: id).process?.terminate()
    }

    private func appendToolOutput(_ chunk: String) {
        toolOutput += chunk
        if toolOutput.count > 200_000 {
            toolOutput.removeFirst(toolOutput.count - 160_000)
        }
    }

    private func reloadFromDisk() async {
        await reloadRegistry()
        await refreshStatus()
    }

    private func reloadRegistry() async {
        guard let root = validatedRoot else {
            registry = nil
            return
        }
        let url = root.appendingPathComponent("scripts/registry.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RegistryFile.self, from: data)
        else {
            registry = nil
            return
        }
        // Drop unknown tools/units from a tampered registry.
        let safeTools = decoded.tools.filter { Safety.knownToolIDs.contains($0.id) }
        let safeUnits = decoded.units.filter { Safety.knownUnitIDs.contains($0.id) }
        registry = RegistryFile(version: decoded.version, units: safeUnits, tools: safeTools)
        if !safeTools.contains(where: { $0.id == selectedToolID }) {
            selectedToolID = safeTools.first?.id ?? selectedToolID
        }
    }

    private func loadStatus() async {
        guard let root = validatedRoot else {
            statusError = "Repository not found. Choose it in Settings."
            units = []
            reloadLog()
            return
        }
        switch Safety.scriptURL(named: "status.sh", root: root) {
        case .failure(let error):
            statusError = error.localizedDescription
            reloadLog()
        case .success(let script):
            let output = await ProcessRunner.run(
                arguments: ["/bin/bash", script.path, "--json"],
                cwd: root,
                extraPath: loginPath
            )
            guard output.code == 0, let document = Self.decodeStatus(output.stdout) else {
                statusError = Self.clip(output.combined, fallback: "status.sh failed (\(output.code))")
                reloadLog()
                return
            }
            statusError = nil
            units = document.units.filter { Safety.knownUnitIDs.contains($0.id) }
            checkedAt = document.checkedAt
            reloadLog()
            for unit in units where unit.isRunning {
                refreshServiceLog(unitID: unit.id)
            }
            if expandedServiceFamilyID != nil {
                refreshExpandedServiceLogs()
            }
        }
    }

    private func runScript(name: String, arguments: [String], busy: String) async {
        guard let root = validatedRoot else {
            actionError = "Choose the Prushka checkout in Settings."
            return
        }
        guard !busyIDs.contains(busy) else { return }

        let scriptURL: URL
        switch Safety.scriptURL(named: name, root: root) {
        case .failure(let error):
            actionError = error.localizedDescription
            return
        case .success(let url):
            scriptURL = url
        }

        let safeArgs: [String]
        switch Safety.validateScriptArguments(arguments) {
        case .failure(let error):
            actionError = error.localizedDescription
            return
        case .success(let args):
            safeArgs = args
        }

        busyIDs.insert(busy)
        actionError = nil
        let output = await ProcessRunner.run(
            arguments: ["/bin/bash", scriptURL.path] + safeArgs,
            cwd: root,
            extraPath: loginPath
        )
        busyIDs.remove(busy)
        if !output.cancelled, output.code != 0 {
            actionError = Self.clip(output.combined, fallback: "\(name) failed (\(output.code))")
        }
        await refreshStatus()
    }

    private func reloadLog() {
        guard let root = validatedRoot else {
            logText = ""
            return
        }
        let preferred = unit(id: selectedLogID)?.logFile
        switch Safety.logFileURL(unitID: selectedLogID, root: root, preferred: preferred) {
        case .success(let url):
            logText = LogTail.read(path: url.path)
        case .failure:
            logText = ""
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                // Avoid fighting the UI while a long tool/check is streaming output.
                if !busyIDs.isEmpty { continue }
                await refreshStatus()
            }
        }
    }

    private func startServiceLogPolling() {
        serviceLogPollTask?.cancel()
        serviceLogPollTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshExpandedServiceLogs()
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func stopServiceLogPolling() {
        serviceLogPollTask?.cancel()
        serviceLogPollTask = nil
    }

    private func refreshExpandedServiceLogs() {
        guard let familyID = expandedServiceFamilyID,
              let family = ServiceCatalog.families.first(where: { $0.id == familyID })
        else { return }
        for variant in family.variants {
            refreshServiceLog(unitID: variant.id)
        }
    }

    private static func clip(_ text: String, fallback: String) -> String {
        let cleaned = text.replacingOccurrences(
            of: #"\u{1B}\[[0-9;]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? fallback : trimmed
        if value.count <= 1_200 {
            return value
        }
        return String(value.prefix(1_200)) + "…"
    }

    private static func decodeStatus(_ raw: String) -> StatusDocument? {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(StatusDocument.self, from: Data(raw.utf8)) {
            return direct
        }
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else {
            return nil
        }
        return try? decoder.decode(StatusDocument.self, from: Data(raw[start...end].utf8))
    }
}

enum Confirm {
    @MainActor
    static func ask(title: String, message: String, confirm: String, style: NSAlert.Style) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

enum LogTail {
    static func read(path: String, maxBytes: Int = 64_000) -> String {
        guard FileManager.default.fileExists(atPath: path),
              let handle = FileHandle(forReadingAtPath: path)
        else {
            return ""
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        let data = handle.readDataToEndOfFile()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }
}
