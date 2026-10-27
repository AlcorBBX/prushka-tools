import Foundation
import Observation

struct ServiceVariant: Identifiable, Equatable, Sendable {
    let id: String
    let chip: String

    var modeOption: ModeOption {
        ModeOption(id: id, chip: chip)
    }
}

struct ServiceFamily: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let group: ServiceGroup
    let variants: [ServiceVariant]
    let defaultVariantID: String

    func variant(id: String) -> ServiceVariant? {
        variants.first { $0.id == id }
    }
}

enum ServiceCatalog {
    static let families: [ServiceFamily] = [
        ServiceFamily(
            id: "web",
            title: "Web",
            group: .clients,
            variants: [
                ServiceVariant(id: "web-dev", chip: "Dev"),
                ServiceVariant(id: "web-prod", chip: "Prod"),
            ],
            defaultVariantID: "web-dev"
        ),
        ServiceFamily(
            id: "desktop",
            title: "Desktop",
            group: .clients,
            variants: [
                ServiceVariant(id: "desktop-dev", chip: "Dev"),
            ],
            defaultVariantID: "desktop-dev"
        ),
        ServiceFamily(
            id: "mobile",
            title: "Mobile",
            group: .clients,
            variants: [
                ServiceVariant(id: "mobile-dev", chip: "Dev"),
            ],
            defaultVariantID: "mobile-dev"
        ),
        ServiceFamily(
            id: "stems",
            title: "Stems",
            group: .workers,
            variants: [
                ServiceVariant(id: "autogen-stems-dev", chip: "Dev"),
                ServiceVariant(id: "autogen-stems-prod", chip: "Prod"),
            ],
            defaultVariantID: "autogen-stems-dev"
        ),
        ServiceFamily(
            id: "api",
            title: "API",
            group: .api,
            variants: [
                ServiceVariant(id: "api-memory", chip: "Memory"),
            ],
            defaultVariantID: "api-memory"
        ),
    ]

    static func families(in group: ServiceGroup) -> [ServiceFamily] {
        families.filter { $0.group == group }
    }

    static func family(containingUnitID id: String) -> ServiceFamily? {
        families.first { family in
            family.variants.contains { $0.id == id }
        }
    }
}

@MainActor
@Observable
final class ServiceLogState: ConsoleTextSource {
    var lastLine = ""
    var logRevision = 0
    var hasContent = false

    @ObservationIgnored
    private var storage = ""

    var consoleText: String { storage }

    func applyFileTail(_ text: String) {
        let capped: String
        if text.count > 48_000 {
            let trimmed = String(text.suffix(36_000))
            if let newline = trimmed.firstIndex(of: "\n") {
                capped = "…\n" + String(trimmed[trimmed.index(after: newline)...])
            } else {
                capped = "…\n" + trimmed
            }
        } else {
            capped = text
        }

        guard capped != storage else { return }
        storage = capped
        hasContent = !capped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let last = capped.split(whereSeparator: \.isNewline).last.map(String.init) {
            let line = last.trimmingCharacters(in: .whitespacesAndNewlines)
            lastLine = line.isEmpty ? "" : String(line.suffix(200))
        } else {
            lastLine = ""
        }
        logRevision &+= 1
    }

    func clear() {
        guard !storage.isEmpty || hasContent || !lastLine.isEmpty else { return }
        storage = ""
        lastLine = ""
        hasContent = false
        logRevision &+= 1
    }
}
