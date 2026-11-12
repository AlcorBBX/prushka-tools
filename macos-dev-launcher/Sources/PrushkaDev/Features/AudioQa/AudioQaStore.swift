import AppKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class AudioQaStore {
    public init() {}

    var screen: AudioQaScreen = .dashboard
    var log = ""
    var running = false
    var error: String?
    var report: AudioQaRunFile?
    var reportURL: URL?
    var compare: AudioQaRunFile?
    var selectedSuite = "basic-dsp"
    var selectedScenario = ""
    var scope = "suite"
    var scenarioFiles: [URL] = []
    var runFiles: [URL] = []

    var draftID = "custom-sine"
    var draftTitle = "Custom sine"
    var draftSuite = "basic-dsp"
    var draftSeed = "1"
    var draftRate = "48000"
    var draftDuration = "1.2"
    var draftKind = "sine"
    var draftRole = "vocal"
    var draftFrequency = "440"
    var draftGain = "0.4"
    var draftFormant = "ah"
    var draftCents = "0"
    var draftVibrato = "0"
    var draftNoise = "white"
    var draftSnr = "20"

    private var process: ManagedProcess?
    private var player: AVAudioPlayer?

    func reload(root: URL) {
        scenarioFiles = Self.jsonFiles(under: root.appendingPathComponent("front/apps/web/src/features/audio-qa/scenarios"))
        let custom = root.appendingPathComponent("front/apps/web/.audio-qa/scenarios")
        scenarioFiles.append(contentsOf: Self.jsonFiles(under: custom))
        runFiles = Self.jsonFiles(under: root.appendingPathComponent("front/apps/web/.audio-qa/runs"))
            .filter { !$0.lastPathComponent.hasPrefix("latest") }
        if selectedScenario.isEmpty {
            selectedScenario = scenarioFiles.first?.path ?? ""
        }
        if report == nil {
            let latest = root.appendingPathComponent("front/apps/web/.audio-qa/runs/latest.json")
            report = Self.readReport(latest)
            if report != nil {
                reportURL = latest
            }
        }
    }

    func run(root: URL, extraPath: String, mode: String? = nil) async {
        var arguments = ["pnpm", "--filter", "@prushka/web", "audio-qa", "run"]
        switch scope {
        case "all":
            arguments.append("--all")
        case "scenario":
            guard !selectedScenario.isEmpty else {
                error = "Choose a scenario file."
                return
            }
            arguments.append(contentsOf: ["--scenario", selectedScenario])
        default:
            arguments.append(contentsOf: ["--suite", selectedSuite])
        }
        if let mode {
            if mode == "direct" || mode == "realtime" {
                arguments.append(contentsOf: ["--mode", mode])
            }
        }
        _ = await launch(arguments: arguments, root: root, extraPath: extraPath, captureReport: true)
    }

    func preview(root: URL, extraPath: String) async {
        let file = saveDraft(root: root)
        let wav = root.appendingPathComponent("front/apps/web/.audio-qa/preview.wav")
        let code = await launch(
            arguments: [
                "pnpm", "--filter", "@prushka/web", "audio-qa", "synthesize",
                "--scenario", file.path, "--out", wav.path,
            ],
            root: root,
            extraPath: extraPath,
            captureReport: false
        )
        guard code == 0 else { return }
        play(url: wav)
    }

    func synthesize(root: URL, extraPath: String, scenario: URL, out: URL) async {
        _ = await launch(
            arguments: [
                "pnpm", "--filter", "@prushka/web", "audio-qa", "synthesize",
                "--scenario", scenario.path, "--out", out.path,
            ],
            root: root,
            extraPath: extraPath,
            captureReport: false
        )
    }

    func saveRegression(root: URL, extraPath: String, scenario: AudioQaScenarioFile) async {
        guard let reference = scenario.referencePath else {
            error = "This result has no reference file yet."
            return
        }
        let referenceURL = URL(fileURLWithPath: reference)
        let data = (try? Data(contentsOf: referenceURL)) ?? Data()
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let scenarioObject = object["scenario"]
        else {
            error = "Could not read the scenario from the reference file."
            return
        }
        let folder = root.appendingPathComponent("front/apps/web/.audio-qa/scenarios")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(scenario.id).json")
        if let encoded = try? JSONSerialization.data(withJSONObject: scenarioObject, options: [.prettyPrinted]) {
            try? encoded.write(to: file)
        }
        _ = await launch(
            arguments: [
                "pnpm", "--filter", "@prushka/web", "audio-qa", "save-regression",
                "--scenario", file.path,
            ],
            root: root,
            extraPath: extraPath,
            captureReport: false
        )
    }

    func cancel() {
        process?.terminate()
    }

    func play(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func export(url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try? FileManager.default.copyItem(at: url, to: destination)
    }

    func loadCompare(url: URL) {
        compare = Self.readReport(url)
    }

    @discardableResult
    func saveDraft(root: URL) -> URL {
        let folder = root.appendingPathComponent("front/apps/web/.audio-qa/scenarios")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(draftID).json")
        let object = draftObject()
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
            try? data.write(to: file)
        }
        reload(root: root)
        selectedScenario = file.path
        return file
    }

    private func draftObject() -> [String: Any] {
        let frequency = Double(draftFrequency) ?? 440
        let gain = Double(draftGain) ?? 0.4
        let duration = Double(draftDuration) ?? 1.2
        let cents = Double(draftCents) ?? 0
        let vibrato = Double(draftVibrato) ?? 0
        let source: [String: Any]
        switch draftKind {
        case "vocal":
            source = [
                "kind": "vocal",
                "id": "voice",
                "formant": draftFormant,
                "gain": gain,
                "notes": [[
                    "id": "note",
                    "startSec": 0,
                    "durationSec": duration,
                    "frequencyHz": frequency,
                    "centsOffset": cents,
                    "vibratoDepthCents": vibrato,
                    "vibratoRateHz": 5.2,
                    "expectedHit": abs(cents) <= 15 && abs(vibrato) <= 15,
                ]],
            ]
        case "noise":
            source = [
                "kind": "noise",
                "id": "noise",
                "color": draftNoise,
                "gain": gain,
                "snrDb": Double(draftSnr) ?? 20,
                "startSec": 0,
                "durationSec": duration,
            ]
        case "accompaniment":
            source = [
                "kind": "accompaniment",
                "id": "band",
                "gain": gain,
                "notes": [[
                    "startSec": 0,
                    "durationSec": duration,
                    "frequencyHz": frequency,
                    "harmonics": [1, 0.5, 0.25],
                ]],
            ]
        default:
            source = [
                "kind": "sine",
                "id": "tone",
                "role": draftRole,
                "frequencyHz": frequency,
                "gain": gain,
                "startSec": 0,
                "durationSec": duration,
                "harmonics": [1, 0.5, 0.25],
                "centsOffset": Double(draftCents) ?? 0,
                "vibratoDepthCents": Double(draftVibrato) ?? 0,
                "vibratoRateHz": 5.2,
            ]
        }
        return [
            "id": draftID,
            "title": draftTitle,
            "suite": draftSuite,
            "seed": Int(draftSeed) ?? 1,
            "sampleRate": Int(draftRate) ?? 48_000,
            "durationSec": duration,
            "sources": [source],
        ]
    }

    private func launch(
        arguments: [String],
        root: URL,
        extraPath: String,
        captureReport: Bool
    ) async -> Int32 {
        if running { return 1 }
        running = true
        error = nil
        log = ""
        let output = await ProcessRunner.run(
            arguments: arguments,
            cwd: root.appendingPathComponent("front"),
            extraPath: extraPath,
            onChunk: { [weak self] chunk in
                Task { @MainActor in
                    self?.log.append(chunk)
                }
            },
            onStart: { [weak self] process in
                Task { @MainActor in
                    self?.process = process
                }
            }
        )
        process = nil
        running = false
        if log.isEmpty {
            log = output.combined
        }
        log = Self.trimPackageManagerTail(log)
        if captureReport {
            let marker = "AUDIO_QA_REPORT "
            if let line = output.stdout.split(separator: "\n").last(where: { $0.hasPrefix(marker) }) {
                let path = line.dropFirst(marker.count)
                let url = URL(fileURLWithPath: String(path))
                report = Self.readReport(url)
                reportURL = url
            }
            reload(root: root)
        }
        if output.cancelled {
            error = "Cancelled."
        } else if output.code != 0 && error == nil {
            error = Self.failureMessage(report: captureReport ? report : nil, code: output.code)
        }
        return output.code
    }

    private static func failureMessage(report: AudioQaRunFile?, code: Int32) -> String {
        guard let report else {
            return "Audio QA exited with code \(code)."
        }
        let names = report.scenarios.filter { !$0.passed }.map(\.id).joined(separator: ", ")
        if names.isEmpty {
            return "Audio QA exited with code \(code)."
        }
        return "\(report.passedCount) passed, \(report.failed) failed: \(names)."
    }

    /// pnpm prints a recursive-run stack after a finished suite exits 1. The report line is the real result.
    private static func trimPackageManagerTail(_ log: String) -> String {
        guard log.contains("AUDIO_QA_REPORT ") else { return log }
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        var kept: [Substring] = []
        for line in lines {
            if line.contains("[ELIFECYCLE]")
                || line.contains("ERR_PNPM_RECURSIVE_RUN_FIRST_FAIL")
                || line.contains("pnpm recursive run") {
                break
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    private static func readReport(_ url: URL) -> AudioQaRunFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AudioQaRunFile.self, from: data)
    }

    private static func jsonFiles(under directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }
}
