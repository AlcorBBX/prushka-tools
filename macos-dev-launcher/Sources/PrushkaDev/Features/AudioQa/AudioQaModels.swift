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

struct AudioQaSectionEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
}

struct AudioQaSuiteEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let section: String
}

enum AudioQaCatalog {
    static let sections: [AudioQaSectionEntry] = [
        AudioQaSectionEntry(id: "signal", title: "Signal", summary: "Pitch, voice activity, noise, and accompaniment"),
        AudioQaSectionEntry(id: "performance", title: "Performance", summary: "Sung phrases, cracks, timing, and register changes"),
        AudioQaSectionEntry(id: "accuracy", title: "Accuracy", summary: "Whether the sung pitch lights the written note chip"),
        AudioQaSectionEntry(id: "saved", title: "Saved", summary: "Scenarios kept from an earlier failure"),
    ]

    static let suites: [AudioQaSuiteEntry] = [
        AudioQaSuiteEntry(id: "basic-dsp", title: "Basic DSP", summary: "Sine, harmonics, level, sample rate, silence, buffer faults", section: "signal"),
        AudioQaSuiteEntry(id: "clean-vocal", title: "Clean Vocal", summary: "Formant vowels, mild vibrato, and portamento", section: "signal"),
        AudioQaSuiteEntry(id: "noise-resistance", title: "Noise Resistance", summary: "White, pink, and brown noise, hum, and clicks", section: "signal"),
        AudioQaSuiteEntry(id: "music-interference", title: "Music Interference", summary: "Instrumental stems that must not count as the singer", section: "signal"),
        AudioQaSuiteEntry(id: "mixed", title: "Mixed Scenarios", summary: "Vocal, accompaniment, and noise together", section: "signal"),
        AudioQaSuiteEntry(id: "realtime", title: "Realtime Processing", summary: "Microphone-sized waits between analysis hops", section: "signal"),
        AudioQaSuiteEntry(id: "vocal-imperfections", title: "Vocal Imperfections", summary: "Detune, timing, missed and extra notes, breaks", section: "performance"),
        AudioQaSuiteEntry(id: "song-performance", title: "Song Performance", summary: "Creep chorus pitches and timings, with cracks, sags, and breaks", section: "performance"),
        AudioQaSuiteEntry(id: "chip-tracking", title: "Chip Tracking", summary: "In-tune, edge, late, short, and wrong-octave takes against the written chip", section: "accuracy"),
        AudioQaSuiteEntry(id: "regression", title: "Regression", summary: "Scenarios saved from a previous failure", section: "saved"),
    ]

    static func suites(in section: String) -> [AudioQaSuiteEntry] {
        suites.filter { $0.section == section }
    }

    static func sectionID(for suiteID: String) -> String {
        suites.first { $0.id == suiteID }?.section ?? sections[0].id
    }
}
