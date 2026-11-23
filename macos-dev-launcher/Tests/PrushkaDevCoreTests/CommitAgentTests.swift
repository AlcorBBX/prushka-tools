import Foundation
import XCTest

@testable import PrushkaDevCore

final class CommitAgentTests: XCTestCase {
    func testCursorArgumentsStayReadOnly() {
        let args = CommitAgentProvider.cursor.arguments(executable: "/bin/agent", model: "", prompt: "P")
        XCTAssertEqual(
            args,
            ["/bin/agent", "-p", "--trust", "--mode", "ask", "--output-format", "text", "--model", "auto", "P"]
        )
    }

    func testClaudeArgumentsDisableToolsAndEndOptionsBeforePrompt() {
        let args = CommitAgentProvider.claude.arguments(executable: "/bin/claude", model: " ", prompt: "--not-a-flag")
        XCTAssertEqual(args.firstIndex(of: "--model").map { args[$0 + 1] }, "haiku")
        XCTAssertEqual(args.first, "/bin/claude")
        XCTAssertEqual(args.last, "--not-a-flag")
        let tools = try? XCTUnwrap(args.firstIndex(of: "--tools"))
        XCTAssertEqual(tools.map { args[$0 + 1] }, "")
        XCTAssertEqual(args[args.count - 2], "--")
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        XCTAssertFalse(args.contains { $0.contains("dangerously") || $0 == "bypassPermissions" })
    }

    func testConfigPersistsProviderAndPerProviderPath() throws {
        let suite = "CommitAgentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(CommitAgentConfig.load(defaults).provider, .cursor)

        CommitAgentConfig(provider: .claude, customPath: " /usr/bin/true ").save(defaults)
        let loaded = CommitAgentConfig.load(defaults)
        XCTAssertEqual(loaded, CommitAgentConfig(provider: .claude, customPath: "/usr/bin/true"))

        defaults.set(CommitAgentProvider.cursor.rawValue, forKey: CommitAgentProvider.defaultsKey)
        XCTAssertEqual(CommitAgentConfig.load(defaults).customPath, "")
    }

    func testModelIsPerProvider() throws {
        let suite = "CommitAgentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        CommitAgentConfig(provider: .claude, customPath: "", model: "sonnet").save(defaults)
        XCTAssertEqual(CommitAgentConfig.load(defaults).effectiveModel, "sonnet")
        defaults.set(CommitAgentProvider.cursor.rawValue, forKey: CommitAgentProvider.defaultsKey)
        XCTAssertEqual(CommitAgentConfig.load(defaults).effectiveModel, "auto")
    }

    func testCustomPathMustBeExecutable() {
        let ok = CommitAgentConfig(provider: .claude, customPath: "/usr/bin/true").resolveExecutable(extraPath: nil)
        XCTAssertEqual(try? ok.get(), "/usr/bin/true")

        let relative = CommitAgentConfig(provider: .claude, customPath: "claude").resolveExecutable(extraPath: nil)
        XCTAssertNil(try? relative.get())

        let notExec = CommitAgentConfig(provider: .claude, customPath: "/etc/hosts").resolveExecutable(extraPath: nil)
        XCTAssertNil(try? notExec.get())
    }
}
