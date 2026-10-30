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
        XCTAssertEqual(snapshot.entries.count, 5)

        let byPath = Dictionary(uniqueKeysWithValues: snapshot.entries.map { ($0.path, $0) })
        XCTAssertEqual(byPath["Sources/Foo.swift"]?.kind, .unstaged)
        XCTAssertEqual(byPath["Sources/Bar.swift"]?.kind, .staged)
        XCTAssertEqual(byPath["Sources/Both.swift"]?.kind, .both)
        XCTAssertEqual(byPath["untracked.txt"]?.kind, .untracked)
        XCTAssertEqual(byPath["new.swift"]?.kind, .staged)
    }

    func testPorcelainDetachedAndEmpty() {
        let detached = GitPorcelain.parse("## HEAD (no branch)\n")
        XCTAssertEqual(detached.branch, "DETACHED")
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
