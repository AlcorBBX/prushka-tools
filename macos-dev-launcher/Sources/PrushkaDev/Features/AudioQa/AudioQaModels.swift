import Foundation

struct AudioQaDistributionFile: Decodable, Sendable {
    var count: Int
    var max: Double
    var mean: Double
    var median: Double
    var p95: Double
}

struct AudioQaVoiceFile: Decodable, Sendable {
    var falseNegatives: Int
    var falsePositives: Int
    var precision: Double
    var recall: Double
}

struct AudioQaMetricsFile: Decodable, Sendable {
    var droppedFrames: Int
    var invalidResults: Int
    var noteFalseNegatives: Int
    var noteFalsePositives: Int
    var overruns: Int
    var pitch: AudioQaDistributionFile
    var processingTimeMs: Double
    var scoreActual: Double?
    var scoreDeviation: Double?
    var scoreExpected: Double?
    var timing: AudioQaDistributionFile
    var underruns: Int
    var voice: AudioQaVoiceFile
}

struct AudioQaPitchPoint: Decodable, Sendable {
    var detectedHz: Double?
    var errorCents: Double?
    var groundTruthHz: Double?
    var groundTruthVoiced: Bool
    var timeSec: Double
}

struct AudioQaScenarioFile: Decodable, Identifiable, Sendable {
    var failures: [String]
    var id: String
    var metrics: AudioQaMetricsFile
    var passed: Bool
    var pitchSeries: [AudioQaPitchPoint]
    var referencePath: String?
    var suite: String
    var title: String
    var wavPath: String?
}

struct AudioQaSummaryFile: Decodable, Sendable {
    var maxAbsCents: Double
    var medianAbsCents: Double
    var p95AbsCents: Double
    var scoreDeviation: Double
    var voicePrecision: Double
    var voiceRecall: Double
}

struct AudioQaDeltaFile: Decodable, Sendable {
    var failed: Int
    var medianAbsCents: Double
}

struct AudioQaSuiteFile: Decodable, Sendable {
    var failed: Int
    var medianAbsCents: Double
    var passed: Int
}

struct AudioQaRunFile: Decodable, Sendable {
    var bySuite: [String: AudioQaSuiteFile]
    var delta: AudioQaDeltaFile?
    var engine: String
    var failed: Int
    var id: String
    var passed: Bool
    var passedCount: Int
    var previousRunId: String?
    var scenarios: [AudioQaScenarioFile]
    var summary: AudioQaSummaryFile
    var total: Int
}

enum AudioQaScreen: String, CaseIterable, Identifiable {
    case dashboard
    case builder
    case suites
    case runner
    case results

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .builder: "Scenario Builder"
        case .suites: "Test Suites"
        case .runner: "Test Runner"
        case .results: "Results"
        }
    }
}

enum AudioQaCatalog {
    static let suites: [(id: String, title: String, summary: String)] = [
        ("basic-dsp", "Basic DSP", "Sine, harmonics, level, sample rate, silence, buffer faults"),
        ("clean-vocal", "Clean Vocal", "Formant vowels, mild vibrato, and portamento"),
        ("vocal-imperfections", "Vocal Imperfections", "Detune, timing, missed and extra notes, breaks"),
        ("noise-resistance", "Noise Resistance", "White, pink, and brown noise, hum, and clicks"),
        ("music-interference", "Music Interference", "Instrumental stems that must not count as the singer"),
        ("mixed", "Mixed Scenarios", "Vocal, accompaniment, and noise together"),
        ("realtime", "Realtime Processing", "Microphone-sized waits between analysis hops"),
        ("regression", "Regression", "Scenarios saved from a previous failure"),
        ("song-performance", "Song Performance", "Creep chorus pitches and timings, with cracks, sags, and breaks"),
    ]
}
