import Foundation
import XCTest

@testable import PrushkaDevCore

final class DecodeTests: XCTestCase {
    func testStatusJSONDecodesExternalUnit() throws {
        let raw = """
        {
          "root": "/tmp/prushka",
          "registry": "/tmp/prushka/scripts/registry.json",
          "checkedAt": "2026-10-27T07:04:45Z",
          "units": [
            {
              "id": "web-dev",
              "label": "Web (Vite dev)",
              "kind": "service",
              "state": "running",
              "source": "external",
              "pid": 46801,
              "pids": [46801],
              "health": "ok",
              "url": "http://127.0.0.1:5173",
              "logFile": "/tmp/prushka/.run/logs/web-dev.log"
            }
          ]
        }
        """
        let document = try JSONDecoder().decode(StatusDocument.self, from: Data(raw.utf8))
        let unit = try XCTUnwrap(document.units.first)
        XCTAssertEqual(unit.id, "web-dev")
        XCTAssertTrue(unit.isRunning)
        XCTAssertTrue(unit.showsExternalBadge)
        XCTAssertEqual(unit.pid, 46801)
    }

    func testStoppedUnitHasNoExternalBadge() throws {
        let raw = """
        {"id":"api-memory","label":"API","kind":"service","state":"stopped","source":"none","pid":null,"pids":[],"health":"unknown","url":null,"logFile":"/tmp/api.log"}
        """
        let unit = try JSONDecoder().decode(UnitStatus.self, from: Data(raw.utf8))
        XCTAssertFalse(unit.isRunning)
        XCTAssertFalse(unit.showsExternalBadge)
        XCTAssertNil(unit.pid)
        XCTAssertNil(unit.url)
    }

    func testRepositoryRegistryDecodes() throws {
        let root = try XCTUnwrap(RepoRoot.walk(from: URL(fileURLWithPath: #filePath)))
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/registry.json"))
        let registry = try JSONDecoder().decode(RegistryFile.self, from: data)
        XCTAssertTrue(registry.units.contains { $0.id == "web-dev" })
        XCTAssertTrue(registry.units.contains { $0.id == "desktop-dev" })
        let fetch = try XCTUnwrap(registry.tools.first { $0.id == "tab-source-fetch" })
        XCTAssertEqual(fetch.args.first { $0.name == "force" }?.defaultBool, false)
        XCTAssertEqual(fetch.shortTitle, "Fetch")
    }

    func testWalkFindsRepoMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("prushka-launcher-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("tools/macos-dev-launcher", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("scripts", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: root.appendingPathComponent("scripts/registry.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        let found = RepoRoot.walk(from: nested.appendingPathComponent("Package.swift"))
        XCTAssertEqual(found?.standardizedFileURL.path, root.standardizedFileURL.path)
    }
}
