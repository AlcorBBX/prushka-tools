import Foundation
import XCTest

@testable import PrushkaDevCore

final class SafetyTests: XCTestCase {
    func testRejectsShellMetacharactersInToolValues() {
        XCTAssertThrowsErrorish(Safety.sanitizeToolValue("rooster;rm -rf", type: "string"))
        XCTAssertThrowsErrorish(Safety.sanitizeToolValue("$(whoami)", type: "string"))
        XCTAssertThrowsErrorish(Safety.sanitizeToolValue("../../etc/passwd", type: "string"))
        XCTAssertNoThrowish(Safety.sanitizeToolValue("rooster", type: "string"))
        XCTAssertNoThrowish(Safety.sanitizeToolValue("9489", type: "number"))
        XCTAssertThrowsErrorish(Safety.sanitizeToolValue("94a9", type: "number"))
    }

    func testOpenOnlyLocalhost() {
        XCTAssertNoThrowish(Safety.openableURL("http://localhost:5173/"))
        XCTAssertNoThrowish(Safety.openableURL("http://127.0.0.1:8080/docs"))
        XCTAssertThrowsErrorish(Safety.openableURL("https://example.com"))
        XCTAssertThrowsErrorish(Safety.openableURL("file:///etc/passwd"))
    }

    func testScriptAllowlist() throws {
        let root = try XCTUnwrap(RepoRoot.walk(from: URL(fileURLWithPath: #filePath)))
        XCTAssertNoThrowish(Safety.scriptURL(named: "status.sh", root: root))
        XCTAssertThrowsErrorish(Safety.scriptURL(named: "evil.sh", root: root))
        XCTAssertThrowsErrorish(Safety.scriptURL(named: "../up.sh", root: root))
        XCTAssertThrowsErrorish(Safety.validateScriptArguments(["web-dev", "--bg", ";rm"]))
    }

    func testRepoRequiresMultipleMarkers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prushka-safety-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("scripts/registry.json"))
        XCTAssertThrowsErrorish(Safety.validateRepo(root.path))
    }

    private func XCTAssertNoThrowish<T>(_ result: Result<T, Safety.Failure>, file: StaticString = #filePath, line: UInt = #line) {
        if case .failure(let error) = result {
            XCTFail("unexpected failure: \(error)", file: file, line: line)
        }
    }

    private func XCTAssertThrowsErrorish<T>(_ result: Result<T, Safety.Failure>, file: StaticString = #filePath, line: UInt = #line) {
        if case .success = result {
            XCTFail("expected failure", file: file, line: line)
        }
    }
}
