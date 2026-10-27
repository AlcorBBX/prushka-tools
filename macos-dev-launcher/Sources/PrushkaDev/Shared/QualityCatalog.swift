import Foundation

enum QualityGroup: String, CaseIterable, Identifiable, Sendable {
    case lint
    case format
    case verify
    case hooks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lint: "Lint"
        case .format: "Format"
        case .verify: "Verify"
        case .hooks: "Git hooks"
        }
    }
}

enum QualityOutcome: String, Sendable, Equatable {
    case idle
    case running
    case succeeded
    case failed
    case cancelled
}

struct QualityVariant: Identifiable, Sendable, Equatable {
    let id: String
    let chip: String
    let summary: String
    let cwd: String
    let command: [String]

    var asJob: QualityJob {
        QualityJob(
            id: id,
            group: .lint, // unused when running via family
            title: chip,
            summary: summary,
            chip: chip,
            cwd: cwd,
            command: command
        )
    }
}

struct QualityJob: Identifiable, Sendable, Equatable {
    let id: String
    let group: QualityGroup
    let title: String
    let summary: String
    let chip: String
    let cwd: String
    let command: [String]
}

struct QualityFamily: Identifiable, Sendable, Equatable {
    let id: String
    let group: QualityGroup
    let title: String
    let variants: [QualityVariant]

    var defaultVariantID: String { variants[0].id }

    func variant(id: String) -> QualityVariant? {
        variants.first { $0.id == id } ?? variants.first
    }

    func job(variantID: String) -> QualityJob? {
        guard let variant = variant(id: variantID) else { return nil }
        return QualityJob(
            id: variant.id,
            group: group,
            title: title,
            summary: variant.summary,
            chip: variant.chip,
            cwd: variant.cwd,
            command: variant.command
        )
    }
}

enum QualityCatalog {
    static let families: [QualityFamily] = [
        QualityFamily(
            id: "lint",
            group: .lint,
            title: "Lint",
            variants: [
                QualityVariant(
                    id: "lint-check",
                    chip: "Check",
                    summary: "oxlint across web and shared packages",
                    cwd: "front",
                    command: ["pnpm", "run", "lint"]
                ),
                QualityVariant(
                    id: "lint-fix",
                    chip: "Fix",
                    summary: "Apply fixable oxlint changes",
                    cwd: "front",
                    command: ["pnpm", "run", "lint:fix"]
                )
            ]
        ),
        QualityFamily(
            id: "format",
            group: .format,
            title: "Format",
            variants: [
                QualityVariant(
                    id: "fmt-check",
                    chip: "Check",
                    summary: "Verify formatting without writing files",
                    cwd: "front",
                    command: ["pnpm", "run", "fmt:check"]
                ),
                QualityVariant(
                    id: "fmt-fix",
                    chip: "Fix",
                    summary: "Rewrite sources with the project formatter",
                    cwd: "front",
                    command: ["pnpm", "run", "fmt"]
                )
            ]
        ),
        QualityFamily(
            id: "typecheck",
            group: .verify,
            title: "Typecheck",
            variants: [
                QualityVariant(
                    id: "typecheck",
                    chip: "Check",
                    summary: "TypeScript project references for web, packages, desktop",
                    cwd: "front",
                    command: ["pnpm", "run", "typecheck"]
                )
            ]
        ),
        QualityFamily(
            id: "test",
            group: .verify,
            title: "Tests",
            variants: [
                QualityVariant(
                    id: "test",
                    chip: "Run",
                    summary: "Unit tests for web and shared packages",
                    cwd: "front",
                    command: ["pnpm", "run", "test"]
                ),
                QualityVariant(
                    id: "test-coverage",
                    chip: "Coverage",
                    summary: "Web unit tests with coverage report",
                    cwd: "front",
                    command: ["pnpm", "run", "test:coverage"]
                )
            ]
        ),
        QualityFamily(
            id: "build",
            group: .verify,
            title: "Build",
            variants: [
                QualityVariant(
                    id: "build",
                    chip: "Run",
                    summary: "Production build for web and linked packages",
                    cwd: "front",
                    command: ["pnpm", "run", "build"]
                )
            ]
        ),
        QualityFamily(
            id: "hooks",
            group: .hooks,
            title: "Hooks",
            variants: [
                QualityVariant(
                    id: "pre-commit",
                    chip: "Commit",
                    summary: "Same as husky: fmt + lint:fix (autofix, re-stage staged files)",
                    cwd: "front",
                    command: ["/bin/sh", ".husky/pre-commit"]
                ),
                QualityVariant(
                    id: "pre-push",
                    chip: "Push",
                    summary: "Same as husky: lint, fmt:check, typecheck, test, build in parallel",
                    cwd: "front",
                    command: ["/bin/sh", ".husky/pre-push"]
                )
            ]
        )
    ]

    static var jobs: [QualityJob] {
        families.flatMap { family in
            family.variants.compactMap { family.job(variantID: $0.id) }
        }
    }

    static func job(id: String) -> QualityJob? {
        jobs.first { $0.id == id }
    }

    static func families(in group: QualityGroup) -> [QualityFamily] {
        families.filter { $0.group == group }
    }
}

@MainActor
@Observable
final class QualityRunState: ConsoleTextSource {
    var outcome: QualityOutcome = .idle
    var lastLine = ""
    var exitCode: Int32?
    /// Bumped on each append so AppKit console can refresh without SwiftUI diffing the log string.
    var logRevision = 0

    @ObservationIgnored
    private var storage = ""

    @ObservationIgnored
    var process: ManagedProcess?

    var isRunning: Bool { outcome == .running }

    /// Raw console buffer; not observed — read from `NSViewRepresentable.updateNSView`.
    var consoleText: String { storage }

    func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        storage += chunk
        // Keep a modest tail — UI only needs recent output, and huge strings freeze layout.
        if storage.count > 48_000 {
            let trimmed = String(storage.suffix(36_000))
            if let newline = trimmed.firstIndex(of: "\n") {
                storage = "…\n" + String(trimmed[trimmed.index(after: newline)...])
            } else {
                storage = "…\n" + trimmed
            }
        }
        if let last = chunk.split(whereSeparator: \.isNewline).last.map(String.init) {
            let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lastLine = String(trimmed.suffix(200))
            }
        }
        logRevision &+= 1
    }

    func resetForRun() {
        outcome = .running
        storage = ""
        lastLine = "Starting…"
        exitCode = nil
        logRevision &+= 1
    }
}
