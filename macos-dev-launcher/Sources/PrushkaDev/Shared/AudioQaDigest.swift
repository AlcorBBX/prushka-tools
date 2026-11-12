import Foundation

enum AudioQaDigest {
    static func load(_ url: URL) -> AudioQaRunFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AudioQaRunFile.self, from: data)
    }

    static func attachingPath(_ data: Data, path: String) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        object["reportPath"] = path
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? data
    }

    static func make(report: AudioQaRunFile, reportPath: String) -> JSONValue {
        let failures = report.scenarios.filter { !$0.passed }.map { scenario -> JSONValue in
            .object([
                "id": .string(scenario.id),
                "title": .string(scenario.title),
                "suite": .string(scenario.suite),
                "failures": .array(scenario.failures.map(JSONValue.string)),
                "pitch": .object([
                    "count": .number(Double(scenario.metrics.pitch.count)),
                    "median": .number(scenario.metrics.pitch.median),
                    "p95": .number(scenario.metrics.pitch.p95),
                    "max": .number(scenario.metrics.pitch.max),
                ]),
                "voice": .object([
                    "precision": .number(scenario.metrics.voice.precision),
                    "recall": .number(scenario.metrics.voice.recall),
                    "falsePositives": .number(Double(scenario.metrics.voice.falsePositives)),
                    "falseNegatives": .number(Double(scenario.metrics.voice.falseNegatives)),
                ]),
                "scoreActual": number(scenario.metrics.scoreActual),
                "scoreExpected": number(scenario.metrics.scoreExpected),
                "scoreDeviation": number(scenario.metrics.scoreDeviation),
                "wavPath": scenario.wavPath.map(JSONValue.string) ?? .null,
                "referencePath": scenario.referencePath.map(JSONValue.string) ?? .null,
                "extremes": .array(extremes(scenario.pitchSeries)),
            ])
        }
        var fields: [String: JSONValue] = [
            "id": .string(report.id),
            "engine": .string(report.engine),
            "passed": .bool(report.passed),
            "passedCount": .number(Double(report.passedCount)),
            "failed": .number(Double(report.failed)),
            "total": .number(Double(report.total)),
            "reportPath": .string(reportPath),
            "summary": .object([
                "medianAbsCents": .number(report.summary.medianAbsCents),
                "p95AbsCents": .number(report.summary.p95AbsCents),
                "maxAbsCents": .number(report.summary.maxAbsCents),
                "voicePrecision": .number(report.summary.voicePrecision),
                "voiceRecall": .number(report.summary.voiceRecall),
                "scoreDeviation": .number(report.summary.scoreDeviation),
            ]),
            "failures": .array(failures),
        ]
        if let delta = report.delta {
            fields["delta"] = .object([
                "failed": .number(Double(delta.failed)),
                "medianAbsCents": .number(delta.medianAbsCents),
            ])
        }
        return .object(fields)
    }

    private static func extremes(_ points: [AudioQaPitchPoint]) -> [JSONValue] {
        let ranked = points.compactMap { point -> (Double, AudioQaPitchPoint)? in
            guard let error = point.errorCents else { return nil }
            return (abs(error), point)
        }
        .sorted { $0.0 > $1.0 }
        let chosen: [AudioQaPitchPoint]
        if ranked.isEmpty {
            chosen = Array(points.filter { $0.detectedHz != nil }.prefix(5))
        } else {
            chosen = ranked.prefix(5).map(\.1)
        }
        return chosen.map(point)
    }

    private static func point(_ point: AudioQaPitchPoint) -> JSONValue {
        .object([
            "timeSec": .number(point.timeSec),
            "detectedHz": number(point.detectedHz),
            "groundTruthHz": number(point.groundTruthHz),
            "groundTruthVoiced": .bool(point.groundTruthVoiced),
            "errorCents": number(point.errorCents),
        ])
    }

    private static func number(_ value: Double?) -> JSONValue {
        value.map(JSONValue.number) ?? .null
    }
}
