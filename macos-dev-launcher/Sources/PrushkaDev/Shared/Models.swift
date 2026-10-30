import Foundation

struct StatusDocument: Decodable, Sendable, Equatable {
    let root: String
    let registry: String?
    let checkedAt: String
    let units: [UnitStatus]
}

struct UnitStatus: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let kind: String
    let state: String
    let source: String
    let pid: Int?
    let pids: [Int]
    let health: String
    let url: String?
    let logFile: String?

    var isRunning: Bool { state == "running" }

    var showsExternalBadge: Bool {
        isRunning && (source == "external" || source == "mixed")
    }
}

struct RegistryFile: Decodable, Sendable, Equatable {
    let version: Int
    let units: [RegistryUnit]
    let tools: [RegistryTool]

    init(version: Int, units: [RegistryUnit], tools: [RegistryTool]) {
        self.version = version
        self.units = units
        self.tools = tools
    }
}

struct RegistryUnit: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let kind: String
    let cwd: String?
    let port: Int?
    let openUrl: String?
    let healthUrl: String?
}

struct RegistryTool: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let cwd: String
    let command: [String]
    let args: [ToolArg]

    var shortTitle: String {
        switch id {
        case "tab-source-fetch": "Fetch"
        case "tab-source-fill": "Fill"
        case "demo-notes-from-lead": "Notes"
        default: label
        }
    }
}

struct ToolArg: Decodable, Identifiable, Sendable, Equatable {
    let name: String
    let flag: String
    let type: String
    let required: Bool
    let defaultBool: Bool?
    let defaultString: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case flag
        case type
        case required
        case defaultValue = "default"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        flag = try container.decode(String.self, forKey: .flag)
        type = try container.decode(String.self, forKey: .type)
        required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false

        guard container.contains(.defaultValue) else {
            defaultBool = nil
            defaultString = nil
            return
        }

        if let value = try? container.decode(Bool.self, forKey: .defaultValue) {
            defaultBool = value
            defaultString = nil
            return
        }
        if let value = try? container.decode(Int.self, forKey: .defaultValue) {
            defaultBool = nil
            defaultString = String(value)
            return
        }
        if let value = try? container.decode(String.self, forKey: .defaultValue) {
            defaultBool = nil
            defaultString = value
            return
        }
        defaultBool = nil
        defaultString = nil
    }
}

enum ServiceGroup: String, CaseIterable, Identifiable, Sendable {
    case clients
    case workers
    case api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clients: "Clients"
        case .workers: "Workers"
        case .api: "API"
        }
    }

    var unitIDs: [String] {
        switch self {
        case .clients: ["web-dev", "web-prod", "desktop-dev", "mobile-dev"]
        case .workers: ["autogen-stems-dev", "autogen-stems-prod"]
        case .api: ["api-memory"]
        }
    }
}

enum UnitFace {
    static func title(for id: String) -> String {
        switch id {
        case "web-dev", "web-prod": "Web"
        case "desktop-dev": "Desktop"
        case "mobile-dev": "Mobile"
        case "autogen-stems-dev", "autogen-stems-prod": "Stems"
        case "api-memory": "API"
        default: id
        }
    }

    static func chip(for id: String) -> String {
        switch id {
        case "web-dev", "desktop-dev", "mobile-dev", "autogen-stems-dev": "Dev"
        case "web-prod", "autogen-stems-prod": "Prod"
        case "api-memory": "Memory"
        default: ""
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case services
    case checks
    case git
    case tools
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .services: "Services"
        case .checks: "Checks"
        case .git: "Git"
        case .tools: "Tools"
        case .logs: "Logs"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .services: "Start, stop, and watch local apps"
        case .checks: "Lint, format, tests, and git hook scenarios"
        case .git: "Stage files, draft a commit message, open lazygit"
        case .tools: "Tab source and demo scripts"
        case .logs: "Output from units started here"
        case .settings: "Checkout path for this launcher"
        }
    }

    var symbol: String {
        switch self {
        case .services: "square.stack.3d.up.fill"
        case .checks: "checkmark.seal.fill"
        case .git: "arrow.triangle.branch"
        case .tools: "wrench.and.screwdriver.fill"
        case .logs: "text.alignleft"
        case .settings: "gearshape.fill"
        }
    }
}
