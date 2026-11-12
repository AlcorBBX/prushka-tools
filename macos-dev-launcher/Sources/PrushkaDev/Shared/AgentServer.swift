import AppKit
import Foundation
import Network

enum AgentToken {
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", generator.next() & 0xff) }.joined()
    }
}

enum AgentEndpointFile {
    static func write(root: URL, port: UInt16, token: String) throws {
        let directory = root.appendingPathComponent(".run", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: ["port": Int(port), "token": token])
        try data.write(to: directory.appendingPathComponent("launcher-agent.json"), options: .atomic)
    }

    static func remove(root: URL) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(".run/launcher-agent.json"))
    }
}

struct AgentJob: Sendable {
    var id: String
    var kind: String
    var state: String
    var error: String?
    var result: Data?

    func summary() -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(id),
            "kind": .string(kind),
            "state": .string(state),
        ]
        if let error {
            fields["error"] = .string(error)
        }
        return .object(fields)
    }

    func data() -> Data {
        var object: [String: Any] = [
            "id": id,
            "kind": kind,
            "state": state,
        ]
        if let error {
            object["error"] = error
        }
        if let result, let parsed = try? JSONSerialization.jsonObject(with: result) {
            object["result"] = parsed
        } else {
            object["result"] = NSNull()
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}

@MainActor
@Observable
public final class AgentCoordinator {
    public private(set) var listening = false
    /// True only while an agent session is driving the app. The listening dot stays separate.
    public private(set) var controlling = false
    /// Where the agent is in the launcher, newest last.
    private(set) var trail: [AgentCursor] = []

    var cursor: AgentCursor? { trail.last }

    private var model: LauncherModel?
    private var audio: AudioQaStore?
    private var server: AgentServer?
    private var token = ""
    private var boundRoot: URL?
    private var jobs: [String: AgentJob] = [:]
    private var terminateObserver: NSObjectProtocol?
    private var controlGeneration = 0
    private var sessionHeld = false
    private var releaseAfterWork = false

    public init() {}

    public func start(model: LauncherModel, audio: AudioQaStore) async {
        guard server == nil, model.rootIsValid else { return }
        self.model = model
        self.audio = audio
        token = AgentToken.make()
        let server = AgentServer { [weak self] request in
            guard let self else {
                return AgentHTTPResponse.json(500, .object(["error": .string("stopped")]))
            }
            return await self.handle(request)
        }
        self.server = server
        observeTerminate()
        do {
            let port = try await server.start()
            guard let root = model.validatedRoot else {
                stop()
                return
            }
            try AgentEndpointFile.write(root: root, port: port, token: token)
            boundRoot = root
            listening = true
        } catch {
            stop()
        }
    }

    public func stop() {
        server?.stop()
        server = nil
        if let boundRoot {
            AgentEndpointFile.remove(root: boundRoot)
        }
        boundRoot = nil
        listening = false
        endControlImmediately()
    }

    private func observeTerminate() {
        guard terminateObserver == nil else { return }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }

    private func handle(_ request: AgentRequest) async -> AgentHTTPResponse {
        guard let model, let audio else {
            return AgentHTTPResponse.json(500, .object(["error": .string("stopped")]))
        }
        switch AgentRouter.route(request, token: token) {
        case .unauthorized:
            return AgentHTTPResponse.json(401, .object(["error": .string("unauthorized")]))
        case .notFound:
            return AgentHTTPResponse.json(404, .object(["error": .string("not found")]))
        case .badRequest(let message):
            return AgentHTTPResponse.json(400, .object(["error": .string(message)]))
        case .command(let command):
            switch command {
            case .control(let active):
                if active {
                    beginControl(held: true)
                } else {
                    requestControlRelease()
                }
                return AgentHTTPResponse.json(200, .object(["active": .bool(controlling)]))
            case .jobs:
                return AgentHTTPResponse.json(200, .object([
                    "jobs": .array(jobs.values.map { $0.summary() }.sorted { left, right in
                        guard case .object(let lhs) = left, case .object(let rhs) = right else { return false }
                        return (lhs["id"]?.string ?? "") < (rhs["id"]?.string ?? "")
                    }),
                ]))
            case .job(let id):
                guard let job = jobs[id] else {
                    return AgentHTTPResponse.json(404, .object(["error": .string("Job not found.")]))
                }
                return AgentHTTPResponse(status: 200, body: job.data())
            default:
                break
            }
            beginControl(held: sessionHeld)
            follow(command)
            if command.startsJob {
                return enqueue(command, model: model, audio: audio)
            }
            let response = await AgentExecutor.run(command, model: model, audio: audio)
            settleControl()
            return response
        }
    }

    private func enqueue(
        _ command: AgentCommand,
        model: LauncherModel,
        audio: AudioQaStore
    ) -> AgentHTTPResponse {
        if let busy = busyID(model, audio) {
            return AgentHTTPResponse.json(409, .object([
                "error": .string("busy"),
                "job": .string(busy),
            ]))
        }
        let id = UUID().uuidString
        let created = AgentJob(id: id, kind: command.kind, state: "running", error: nil, result: nil)
        jobs[id] = created
        Task { @MainActor in
            let response = await AgentExecutor.run(command, model: model, audio: audio)
            var finished = self.jobs[id] ?? created
            finished.state = response.status >= 400 ? "failed" : "succeeded"
            finished.result = response.body
            if response.status >= 400,
               let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
               let message = object["error"] as? String {
                finished.error = message
            }
            self.jobs[id] = finished
            self.revealReport(command)
            self.settleControl()
        }
        return AgentHTTPResponse.json(202, .object([
            "id": .string(id),
            "kind": .string(command.kind),
            "state": .string("running"),
        ]))
    }

    private var workIsRunning: Bool {
        jobs.values.contains { $0.state == "running" }
    }

    private func beginControl(held: Bool) {
        controlling = true
        releaseAfterWork = false
        if held { sessionHeld = true }
        armControlTimeout(after: sessionHeld ? 90 : 6)
    }

    private func requestControlRelease() {
        sessionHeld = false
        if workIsRunning {
            releaseAfterWork = true
            return
        }
        endControlImmediately()
    }

    private func settleControl() {
        guard !workIsRunning else { return }
        if releaseAfterWork {
            endControlImmediately()
            return
        }
        armControlTimeout(after: sessionHeld ? 90 : 6)
    }

    private func endControlImmediately() {
        controlGeneration += 1
        sessionHeld = false
        releaseAfterWork = false
        controlling = false
        trail = []
    }

    private func follow(_ command: AgentCommand) {
        guard let model, let audio else { return }
        let token = (trail.last?.token ?? 0) + 1
        let next = AgentPresence.apply(command, model: model, audio: audio, token: token)
        trail.append(next)
        if trail.count > 6 {
            trail.removeFirst(trail.count - 6)
        }
    }

    private func revealReport(_ command: AgentCommand) {
        guard case .audioRun = command, audio?.report != nil else { return }
        audio?.screen = .results
        let token = (trail.last?.token ?? 0) + 1
        trail.append(AgentPresence.results(token: token))
        if trail.count > 6 {
            trail.removeFirst(trail.count - 6)
        }
    }

    private func armControlTimeout(after seconds: Double) {
        controlGeneration += 1
        let generation = controlGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard generation == self.controlGeneration else { return }
            if self.workIsRunning {
                self.armControlTimeout(after: 1)
                return
            }
            self.sessionHeld = false
            self.controlling = false
        }
    }

    private func busyID(_ model: LauncherModel, _ audio: AudioQaStore) -> String? {
        if let running = jobs.values.first(where: { $0.state == "running" }) {
            return running.id
        }
        if audio.running { return "audio-qa" }
        if model.gitBusy || model.gitGenerating { return "git" }
        if !model.busyIDs.isEmpty { return "process" }
        if model.qualityRuns.values.contains(where: \.isRunning) { return "check" }
        return nil
    }
}

private extension JSONValue {
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

final class AgentServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "prushka.agent")
    private let onRequest: @Sendable (AgentRequest) async -> AgentHTTPResponse
    private let gate = NSLock()
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var readyDone = false

    init(onRequest: @escaping @Sendable (AgentRequest) async -> AgentHTTPResponse) {
        self.onRequest = onRequest
    }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            self?.observe(state, listener: listener)
        }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            Task {
                await self?.serve(connection)
            }
        }
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            gate.lock()
            ready = continuation
            gate.unlock()
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        finish(Result.failure(CancellationError()))
    }

    private func observe(_ state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            let port = listener.port?.rawValue ?? 0
            if port == 0 {
                finish(.failure(CancellationError()))
            } else {
                finish(.success(port))
            }
        case .failed(let error):
            finish(.failure(error))
        case .cancelled:
            finish(.failure(CancellationError()))
        default:
            break
        }
    }

    private func finish(_ result: Result<UInt16, Error>) {
        gate.lock()
        let continuation = ready
        ready = nil
        let done = readyDone
        readyDone = true
        gate.unlock()
        guard !done else { return }
        continuation?.resume(with: result)
    }

    private func serve(_ connection: NWConnection) async {
        guard remoteIsLoopback(connection) else {
            await send(connection, AgentHTTP.response(status: 403, body: Data("{\"error\":\"forbidden\"}".utf8)))
            return
        }
        var buffer = Data()
        while buffer.count < 1_048_576 {
            let received = await receive(connection)
            if let chunk = received.chunk, !chunk.isEmpty {
                buffer.append(chunk)
            }
            switch AgentHTTP.parse(buffer) {
            case .incomplete:
                if received.done {
                    await send(connection, AgentHTTP.response(status: 400, body: Data("{\"error\":\"incomplete\"}".utf8)))
                    return
                }
            case .tooLarge:
                await send(connection, AgentHTTP.response(status: 413, body: Data("{\"error\":\"too large\"}".utf8)))
                return
            case .ready(let request):
                let response = await onRequest(request)
                await send(connection, AgentHTTP.response(status: response.status, body: response.body))
                return
            }
            if received.done { break }
        }
        await send(connection, AgentHTTP.response(status: 400, body: Data("{\"error\":\"incomplete\"}".utf8)))
    }

    private func receive(_ connection: NWConnection) async -> (chunk: Data?, done: Bool) {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                continuation.resume(returning: (data, isComplete || error != nil))
            }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in
                continuation.resume()
            })
        }
        connection.cancel()
    }

    private func remoteIsLoopback(_ connection: NWConnection) -> Bool {
        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address):
                return address == .loopback
            case .ipv6(let address):
                return address == .loopback
            case .name(let name, _):
                return name == "localhost" || name == "127.0.0.1" || name == "::1"
            @unknown default:
                return false
            }
        default:
            // The listener itself is bound to 127.0.0.1, so a missing peer address is still local.
            return true
        }
    }
}
