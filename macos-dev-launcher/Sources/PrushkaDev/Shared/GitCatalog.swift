import Foundation

struct NestedGitRepo: Identifiable, Sendable, Equatable, Hashable {
    let id: String
    let label: String
    let relativePath: String

    var title: String { label }
}

enum GitCatalog {
    static let repos: [NestedGitRepo] = [
        NestedGitRepo(id: "front", label: "front", relativePath: "front"),
        NestedGitRepo(id: "tools", label: "tools", relativePath: "tools"),
        NestedGitRepo(id: "scripts", label: "scripts", relativePath: "scripts")
    ]

    static func repo(id: String) -> NestedGitRepo? {
        repos.first { $0.id == id }
    }
}

enum GitPathKind: String, Sendable, Equatable {
    case staged
    case unstaged
    case untracked
    case both
}

struct GitFileEntry: Identifiable, Sendable, Equatable {
    var id: String { path }
    let path: String
    let indexStatus: Character
    let workTreeStatus: Character
    let kind: GitPathKind

    var statusLabel: String {
        switch kind {
        case .staged: "Staged"
        case .unstaged: "Unstaged"
        case .untracked: "Untracked"
        case .both: "Staged+dirty"
        }
    }

    var codeLabel: String {
        String([indexStatus == " " ? "_" : indexStatus, workTreeStatus == " " ? "_" : workTreeStatus])
    }
}

struct GitStatusSnapshot: Sendable, Equatable {
    var branch: String
    var entries: [GitFileEntry]
    var raw: String

    static let empty = GitStatusSnapshot(branch: "", entries: [], raw: "")
}

enum GitPorcelain {
    /// Parses `git status --porcelain=v1 -b` output.
    static func parse(_ text: String) -> GitStatusSnapshot {
        var branch = ""
        var entries: [GitFileEntry] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("## ") {
                branch = parseBranch(String(line.dropFirst(3)))
                continue
            }
            guard line.count >= 3 else { continue }
            let indexStatus = line[line.startIndex]
            let workTreeStatus = line[line.index(line.startIndex, offsetBy: 1)]
            var pathPart = String(line.dropFirst(3))
            // Rename: "R  old -> new" — use the new path.
            if let arrow = pathPart.range(of: " -> ") {
                pathPart = String(pathPart[arrow.upperBound...])
            }
            pathPart = stripQuotes(pathPart)
            guard !pathPart.isEmpty else { continue }
            let kind = classify(index: indexStatus, workTree: workTreeStatus)
            entries.append(
                GitFileEntry(
                    path: pathPart,
                    indexStatus: indexStatus,
                    workTreeStatus: workTreeStatus,
                    kind: kind
                )
            )
        }
        return GitStatusSnapshot(branch: branch, entries: entries, raw: text)
    }

    private static func parseBranch(_ header: String) -> String {
        // "main...origin/main [ahead 1]" or "No commits yet on main" or "HEAD (no branch)"
        let base = header.split(separator: "...", maxSplits: 1).first.map(String.init) ?? header
        if base.hasPrefix("No commits yet on ") {
            return String(base.dropFirst("No commits yet on ".count))
        }
        if base.hasPrefix("HEAD (no branch)") {
            return "DETACHED"
        }
        return base.trimmingCharacters(in: .whitespaces)
    }

    private static func classify(index: Character, workTree: Character) -> GitPathKind {
        if index == "?" && workTree == "?" {
            return .untracked
        }
        let staged = index != " " && index != "?"
        let dirty = workTree != " " && workTree != "?"
        if staged && dirty { return .both }
        if staged { return .staged }
        if workTree == "?" { return .untracked }
        return .unstaged
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}
