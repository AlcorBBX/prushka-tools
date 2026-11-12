import Foundation
import XCTest

@testable import PrushkaDevCore

final class AgentRouterTests: XCTestCase {
    func testRejectsMissingAndWrongToken() {
        let catalog = request(method: "GET", path: "/v1/catalog")
        XCTAssertEqual(AgentRouter.route(catalog, token: "secret"), .unauthorized)

        var wrong = catalog
        wrong.headers["authorization"] = "Bearer other"
        XCTAssertEqual(AgentRouter.route(wrong, token: "secret"), .unauthorized)
    }

    func testSettingsAndShellAreNotRoutes() {
        let token = "secret"
        XCTAssertEqual(
            AgentRouter.route(request(method: "GET", path: "/v1/settings", token: token), token: token),
            .notFound
        )
        XCTAssertEqual(
            AgentRouter.route(request(method: "POST", path: "/v1/settings/root", token: token), token: token),
            .notFound
        )
        XCTAssertEqual(
            AgentRouter.route(request(method: "POST", path: "/v1/shell", token: token), token: token),
            .notFound
        )
        XCTAssertEqual(
            AgentRouter.route(request(method: "POST", path: "/v1/rebuild", token: token), token: token),
            .notFound
        )
    }

    func testControlRequiresActiveFlag() {
        let token = "secret"
        let missing = request(method: "POST", path: "/v1/control", token: token)
        XCTAssertEqual(AgentRouter.route(missing, token: token), .badRequest("active is required"))

        var engaged = missing
        engaged.body = Data(#"{"active":true}"#.utf8)
        XCTAssertEqual(AgentRouter.route(engaged, token: token), .command(.control(active: true)))

        var released = missing
        released.body = Data(#"{"active":false}"#.utf8)
        XCTAssertEqual(AgentRouter.route(released, token: token), .command(.control(active: false)))
    }

    func testStopAllRequiresConfirmation() {
        let token = "secret"
        let missing = request(method: "POST", path: "/v1/services/stop-all", token: token)
        XCTAssertEqual(AgentRouter.route(missing, token: token), .badRequest("confirmed is required"))

        var confirmed = missing
        confirmed.body = Data(#"{"confirmed":true}"#.utf8)
        XCTAssertEqual(AgentRouter.route(confirmed, token: token), .command(.stopAll))
    }

    func testUnknownUnitIsNotARoute() {
        let token = "secret"
        let decision = AgentRouter.route(
            request(method: "POST", path: "/v1/services/not-a-unit/start", token: token),
            token: token
        )
        XCTAssertEqual(decision, .notFound)
    }

    func testDigestKeepsFailuresAndDropsTheSeries() throws {
        let report = AudioQaRunFile(
            bySuite: ["music-interference": AudioQaSuiteFile(failed: 1, medianAbsCents: 0, passed: 0)],
            delta: nil,
            engine: "voice-pipeline+karaoke-accuracy-tracker",
            failed: 1,
            id: "run-1",
            passed: false,
            passedCount: 0,
            previousRunId: nil,
            scenarios: [
                AudioQaScenarioFile(
                    failures: ["voice precision 0.000 < 0.95"],
                    id: "accompaniment-only",
                    metrics: AudioQaMetricsFile(
                        droppedFrames: 0,
                        invalidResults: 0,
                        noteFalseNegatives: 0,
                        noteFalsePositives: 0,
                        overruns: 0,
                        pitch: AudioQaDistributionFile(count: 0, max: 0, mean: 0, median: 0, p95: 0),
                        processingTimeMs: 4,
                        scoreActual: nil,
                        scoreDeviation: nil,
                        scoreExpected: nil,
                        timing: AudioQaDistributionFile(count: 0, max: 0, mean: 0, median: 0, p95: 0),
                        underruns: 0,
                        voice: AudioQaVoiceFile(falseNegatives: 0, falsePositives: 22, precision: 0, recall: 1)
                    ),
                    passed: false,
                    pitchSeries: (0..<8).map { index in
                        AudioQaPitchPoint(
                            detectedHz: 440,
                            errorCents: nil,
                            groundTruthHz: nil,
                            groundTruthVoiced: false,
                            timeSec: Double(index) * 0.04
                        )
                    },
                    referencePath: "/tmp/reference.json",
                    suite: "music-interference",
                    title: "Instrument in the vocal range, no singer",
                    wavPath: "/tmp/accompaniment.wav"
                )
            ],
            summary: AudioQaSummaryFile(
                maxAbsCents: 0,
                medianAbsCents: 0,
                p95AbsCents: 0,
                scoreDeviation: 0,
                voicePrecision: 0,
                voiceRecall: 1
            ),
            total: 1
        )

        let digest = AudioQaDigest.make(report: report, reportPath: "/tmp/run.json")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: digest.data()) as? [String: Any])
        XCTAssertEqual((object["failed"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual(object["reportPath"] as? String, "/tmp/run.json")
        let failures = try XCTUnwrap(object["failures"] as? [[String: Any]])
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures[0]["id"] as? String, "accompaniment-only")
        let messages = try XCTUnwrap(failures[0]["failures"] as? [String])
        XCTAssertEqual(messages, ["voice precision 0.000 < 0.95"])
        XCTAssertNil(failures[0]["pitchSeries"])
        let extremes = try XCTUnwrap(failures[0]["extremes"] as? [[String: Any]])
        XCTAssertEqual(extremes.count, 5)
        XCTAssertEqual((extremes[0]["detectedHz"] as? NSNumber)?.doubleValue, 440)
    }

    func testLoopbackRejectsAMissingToken() async throws {
        let server = AgentServer { request in
            if case .unauthorized = AgentRouter.route(request, token: "secret") {
                return AgentHTTPResponse.json(401, .object(["error": .string("unauthorized")]))
            }
            return AgentHTTPResponse.json(200, .object(["ok": .bool(true)]))
        }
        let port = try await server.start()
        defer { server.stop() }

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/catalog"))
        var missing = URLRequest(url: url)
        missing.timeoutInterval = 5
        let (_, denied) = try await URLSession.shared.data(for: missing)
        XCTAssertEqual((denied as? HTTPURLResponse)?.statusCode, 401)

        var allowed = missing
        allowed.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let (_, accepted) = try await URLSession.shared.data(for: allowed)
        XCTAssertEqual((accepted as? HTTPURLResponse)?.statusCode, 200)
    }

    private func request(method: String, path: String, token: String? = nil) -> AgentRequest {
        var headers: [String: String] = [:]
        if let token {
            headers["authorization"] = "Bearer \(token)"
        }
        return AgentRequest(method: method, path: path, query: [:], headers: headers, body: Data())
    }
}
