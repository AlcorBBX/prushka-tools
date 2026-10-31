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

struct GitCommitEntry: Identifiable, Sendable, Equatable {
    var id: String { hash }
    let hash: String
    let subject: String
}

struct GitStatusSnapshot: Sendable, Equatable {
    var branch: String
    var upstream: String?
    var ahead: Int
    var behind: Int
    var entries: [GitFileEntry]
    var raw: String

    var hasUpstream: Bool { upstream != nil }

    static let empty = GitStatusSnapshot(
        branch: "",
        upstream: nil,
        ahead: 0,
        behind: 0,
        entries: [],
        raw: ""
    )
}

enum GitPorcelain {
    /// Parses `git status --porcelain=v1 -b` output.
    static func parse(_ text: String) -> GitStatusSnapshot {
        var branch = ""
        var upstream: String?
        var ahead = 0
        var behind = 0
        var entries: [GitFileEntry] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("## ") {
                let info = parseBranchHeader(String(line.dropFirst(3)))
                branch = info.branch
                upstream = info.upstream
                ahead = info.ahead
                behind = info.behind
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
        return GitStatusSnapshot(
            branch: branch,
            upstream: upstream,
            ahead: ahead,
            behind: behind,
            entries: entries,
            raw: text
        )
    }

    /// Parses `hash\\tsubject` lines from `git log --format=%h%x09%s`.
    static func parseCommitLines(_ text: String) -> [GitCommitEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let raw = String(line)
            guard let tab = raw.firstIndex(of: "\t") else { return nil }
            let hash = String(raw[..<tab]).trimmingCharacters(in: .whitespaces)
            let subject = String(raw[raw.index(after: tab)...]).trimmingCharacters(in: .whitespaces)
            guard !hash.isEmpty, !subject.isEmpty else { return nil }
            return GitCommitEntry(hash: hash, subject: subject)
        }
    }

    private static func parseBranchHeader(_ header: String) -> (
        branch: String,
        upstream: String?,
        ahead: Int,
        behind: Int
    ) {
        // "main...origin/main [ahead 1, behind 2]" / "main" / "No commits yet on main" / "HEAD (no branch)"
        var working = header
        var ahead = 0
        var behind = 0
        if let bracket = working.range(of: " [") {
            let meta = String(working[bracket.upperBound...])
            ahead = parseCount(in: meta, label: "ahead")
            behind = parseCount(in: meta, label: "behind")
            working = String(working[..<bracket.lowerBound])
        }

        if working.hasPrefix("No commits yet on ") {
            return (String(working.dropFirst("No commits yet on ".count)), nil, 0, 0)
        }
        if working.hasPrefix("HEAD (no branch)") {
            return ("DETACHED", nil, 0, 0)
        }

        if let dots = working.range(of: "...") {
            let branch = String(working[..<dots.lowerBound]).trimmingCharacters(in: .whitespaces)
            let upstream = String(working[dots.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (branch, upstream.isEmpty ? nil : upstream, ahead, behind)
        }

        return (working.trimmingCharacters(in: .whitespaces), nil, ahead, behind)
    }

    private static func parseCount(in meta: String, label: String) -> Int {
        // "[ahead 2, behind 1]" or "[ahead 2]"
        guard let range = meta.range(of: "\\b\(label) (\\d+)", options: .regularExpression) else {
            return 0
        }
        let token = String(meta[range])
        let digits = token.split(separator: " ").last.map(String.init) ?? "0"
        return Int(digits) ?? 0
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
