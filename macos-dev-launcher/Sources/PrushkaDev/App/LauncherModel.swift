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

    private var didBoot = false
    private var loginPath = ""
    private var pollTask: Task<Void, Never>?
    private var statusChain: Task<Void, Never>?
    private var activeProcess: ManagedProcess?

    var rootIsValid: Bool {
        RepoRoot.isRepo(repoRoot)
    }

    var tools: [RegistryTool] {
        registry?.tools ?? []
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
        UserDefaults.standard.set(trimmed, forKey: RepoRoot.defaultsKey)
        repoRoot = trimmed
        Task { await reloadFromDisk() }
    }

    func useDetectedRoot() {
        UserDefaults.standard.removeObject(forKey: RepoRoot.defaultsKey)
        detectedRoot = RepoRoot.resolve(ignoringSaved: true)
        repoRoot = detectedRoot
        Task { await reloadFromDisk() }
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
        await runScript(name: "up.sh", arguments: [unitID, "--bg"], busy: unitID)
    }

    func stop(unitID: String) async {
        await runScript(name: "down.sh", arguments: [unitID], busy: unitID)
    }

    func startDefault() async {
        await runScript(name: "up.sh", arguments: ["dev", "all"], busy: "bundle")
    }

    func stopAll() async {
        await runScript(name: "down.sh", arguments: [], busy: "bundle")
    }

    func openTarget(for id: String) -> String? {
        if let openURL = registry?.units.first(where: { $0.id == id })?.openUrl {
            return openURL
        }
        return unit(id: id)?.url
    }

    func open(urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func selectLog(_ id: String) {
        selectedLogID = id
        reloadLog()
    }

    func run(tool: RegistryTool, text: [String: String], flags: [String: Bool]) async {
        guard rootIsValid else {
            actionError = "Choose the Prushka checkout in Settings."
            return
        }
        let busy = "tool:\(tool.id)"
        guard !busyIDs.contains(busy) else { return }

        var arguments = tool.command
        for arg in tool.args {
            if arg.type == "boolean" {
                if flags[arg.name] == true {
                    arguments.append(arg.flag)
                }
                continue
            }
            let value = text[arg.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                if arg.required {
                    actionError = "\(tool.label) needs \(arg.name)."
                    return
                }
                continue
            }
            arguments.append(arg.flag)
            arguments.append(value)
        }

        busyIDs.insert(busy)
        actionError = nil
        toolOutput = ""
        toolOutputTitle = tool.label
        let cwd = URL(fileURLWithPath: repoRoot).appendingPathComponent(tool.cwd)
        let output = await ProcessRunner.run(
            arguments: arguments,
            cwd: cwd,
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
        let url = URL(fileURLWithPath: repoRoot).appendingPathComponent("scripts/registry.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(RegistryFile.self, from: data)
        else {
            registry = nil
            return
        }
        registry = decoded
        if !decoded.tools.contains(where: { $0.id == selectedToolID }) {
            selectedToolID = decoded.tools.first?.id ?? selectedToolID
        }
    }

    private func loadStatus() async {
        guard rootIsValid else {
            statusError = "Repository not found. Choose it in Settings."
            units = []
            reloadLog()
            return
        }
        let script = URL(fileURLWithPath: repoRoot).appendingPathComponent("scripts/status.sh").path
        let output = await ProcessRunner.run(
            arguments: ["/bin/bash", script, "--json"],
            cwd: URL(fileURLWithPath: repoRoot),
            extraPath: loginPath
        )
        guard output.code == 0, let document = Self.decodeStatus(output.stdout) else {
            statusError = Self.clip(output.combined, fallback: "status.sh failed (\(output.code))")
            reloadLog()
            return
        }
        statusError = nil
        units = document.units
        checkedAt = document.checkedAt
        reloadLog()
    }

    private func runScript(name: String, arguments: [String], busy: String) async {
        guard rootIsValid else {
            actionError = "Choose the Prushka checkout in Settings."
            return
        }
        guard !busyIDs.contains(busy) else { return }
        busyIDs.insert(busy)
        actionError = nil
        let script = URL(fileURLWithPath: repoRoot).appendingPathComponent("scripts/\(name)").path
        let output = await ProcessRunner.run(
            arguments: ["/bin/bash", script] + arguments,
            cwd: URL(fileURLWithPath: repoRoot),
            extraPath: loginPath
        )
        busyIDs.remove(busy)
        if !output.cancelled, output.code != 0 {
            actionError = Self.clip(output.combined, fallback: "\(name) failed (\(output.code))")
        }
        await refreshStatus()
    }

    private func reloadLog() {
        logText = LogTail.read(path: logPath(for: selectedLogID))
    }

    private func logPath(for id: String) -> String {
        if let file = unit(id: id)?.logFile, !file.isEmpty {
            return file
        }
        return URL(fileURLWithPath: repoRoot)
            .appendingPathComponent(".run/logs/\(id).log")
            .path
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                await refreshStatus()
            }
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
