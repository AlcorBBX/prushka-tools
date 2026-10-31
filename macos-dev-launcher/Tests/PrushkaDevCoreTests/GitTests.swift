import Foundation
import XCTest

@testable import PrushkaDevCore

final class GitTests: XCTestCase {
    func testPorcelainParsesBranchAndEntries() {
        let raw = """
        ## main...origin/main [ahead 1]
         M Sources/Foo.swift
        A  Sources/Bar.swift
        MM Sources/Both.swift
        ?? untracked.txt
        R  old.swift -> new.swift
        """
        let snapshot = GitPorcelain.parse(raw)
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertEqual(snapshot.upstream, "origin/main")
        XCTAssertEqual(snapshot.ahead, 1)
        XCTAssertEqual(snapshot.behind, 0)
        XCTAssertEqual(snapshot.entries.count, 5)

        let byPath = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.path, $0) })
        XCTAssertEqual(byPath["Sources/Foo.swift"]?.kind, .unstaged)
        XCTAssertEqual(byPath["Sources/Bar.swift"]?.kind, .staged)
        XCTAssertEqual(byPath["Sources/Both.swift"]?.kind, .both)
        XCTAssertEqual(byPath["untracked.txt"]?.kind, .untracked)
        XCTAssertEqual(byPath["new.swift"]?.kind, .staged)
    }

    func testPorcelainParsesAheadBehindAndNoUpstream() {
        let both = GitPorcelain.parse("## feature...origin/feature [ahead 3, behind 2]\n")
        XCTAssertEqual(both.branch, "feature")
        XCTAssertEqual(both.upstream, "origin/feature")
        XCTAssertEqual(both.ahead, 3)
        XCTAssertEqual(both.behind, 2)

        let local = GitPorcelain.parse("## wip\n")
        XCTAssertEqual(local.branch, "wip")
        XCTAssertNil(local.upstream)
        XCTAssertEqual(local.ahead, 0)
    }

    func testParseCommitLines() {
        let commits = GitPorcelain.parseCommitLines("""
        a1b2c3d\tfeat(GitView): Add push button
        deadbeef\tfix(Safety): Tighten paths
        """)
        XCTAssertEqual(commits.count, 2)
        XCTAssertEqual(commits[0].hash, "a1b2c3d")
        XCTAssertEqual(commits[0].subject, "feat(GitView): Add push button")
    }

    func testPorcelainDetachedAndEmpty() {
        let detached = GitPorcelain.parse("## HEAD (no branch)\n")
        XCTAssertEqual(detached.branch, "DETACHED")
        XCTAssertNil(detached.upstream)
        XCTAssertTrue(detached.entries.isEmpty)

        let empty = GitPorcelain.parse("")
        XCTAssertEqual(empty, .empty)
    }

    func testSanitizeGitPathsRejectsEscape() {
        XCTAssertThrowsErrorish(Safety.sanitizeGitPaths(["../etc/passwd"]))
        XCTAssertThrowsErrorish(Safety.sanitizeGitPaths(["/tmp/x"]))
        XCTAssertThrowsErrorish(Safety.sanitizeGitPaths(["foo;rm"]))
        XCTAssertThrowsErrorish(Safety.sanitizeGitPaths([]))
        XCTAssertNoThrowish(Safety.sanitizeGitPaths(["Sources/Foo.swift"]))
        XCTAssertNoThrowish(Safety.sanitizeGitPaths(["nested/path/file.ts"]))
    }

    func testUnknownGitRepoRejected() {
        let fake = NestedGitRepo(id: "evil", label: "evil", relativePath: "evil")
        let root = URL(fileURLWithPath: "/tmp")
        XCTAssertThrowsErrorish(Safety.gitRepoURL(repo: fake, root: root))
    }

    func testGitRepoRequiresDotGit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prushka-git-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let front = root.appendingPathComponent("front", isDirectory: true)
        try FileManager.default.createDirectory(at: front, withIntermediateDirectories: true)
        let repo = try XCTUnwrap(GitCatalog.repo(id: "front"))
        XCTAssertThrowsErrorish(Safety.gitRepoURL(repo: repo, root: root))

        try FileManager.default.createDirectory(
            at: front.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        XCTAssertNoThrowish(Safety.gitRepoURL(repo: repo, root: root))
    }

    func testCommitMessageSanitizeStripsFences() {
        let fenced = """
        ```
        fix: tidy git status UI

        Keep the list readable.
        ```
        """
        let cleaned = CommitMessageGenerator.sanitizeMessage(fenced)
        XCTAssertTrue(cleaned.hasPrefix("fix:"))
        XCTAssertFalse(cleaned.contains("```"))
    }

    func testSanitizeCommitMessage() {
        XCTAssertThrowsErrorish(Safety.sanitizeCommitMessage("   "))
        XCTAssertThrowsErrorish(Safety.sanitizeCommitMessage("bad\0null"))
        XCTAssertNoThrowish(Safety.sanitizeCommitMessage("feat(GitView): Add commit button"))
    }

    func testPromptRequiresScope() {
        let prompt = CommitMessageGenerator.buildPrompt(
            repoLabel: "tools",
            statusText: "M Sources/Foo.swift",
            cachedDiff: "diff --git a/Sources/Foo.swift",
            shortLog: "feat(ProcessRunner): Enhance PATH"
        )
        XCTAssertTrue(prompt.contains("ALWAYS include a scope"))
        XCTAssertTrue(prompt.contains("feat(ProcessRunner):"))
    }

    private func XCTAssertNoThrowish<T>(
        _ result: Result<T, Safety.Failure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .failure(let error) = result {
            XCTFail("unexpected failure: \(error)", file: file, line: line)
        }
    }

    private func XCTAssertThrowsErrorish<T>(
        _ result: Result<T, Safety.Failure>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .success = result {
            XCTFail("expected failure", file: file, line: line)
        }
    }
}
