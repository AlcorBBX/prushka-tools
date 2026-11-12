import SwiftUI

struct AudioQaView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(AudioQaStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.rootIsValid {
                GroupedCard {
                    Text("Point Settings at the Prushka checkout. Audio QA runs from front/.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            } else {
                screenPicker
                if let error = store.error {
                    ErrorBanner(message: error)
                }
                switch store.screen {
                case .dashboard:
                    dashboard
                case .builder:
                    builder
                case .suites:
                    suites
                case .runner:
                    runner
                case .results:
                    results
                }
            }
        }
        .onAppear { reload() }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: store.screen)
    }

    private var screenPicker: some View {
        Picker("Screen", selection: binding(\.screen)) {
            ForEach(AudioQaScreen.allCases) { screen in
                Text(screen.title).tag(screen)
            }
        }
        .pickerStyle(.segmented)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Last run")
            GroupedCard {
                if let report = store.report {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(report.total) tests · \(report.passedCount) passed · \(report.failed) failed")
                            .font(.headline)
                        Text(report.passed ? "Last result passed" : "Last result failed")
                            .foregroundStyle(report.passed ? Color.green : Color.red)
                        Text("Median \(format(report.summary.medianAbsCents)) cents · p95 \(format(report.summary.p95AbsCents)) · max \(format(report.summary.maxAbsCents))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Voice precision \(format(report.summary.voicePrecision)) · recall \(format(report.summary.voiceRecall)) · score deviation \(format(report.summary.scoreDeviation))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let delta = report.delta {
                            Text("Compared with \(report.previousRunId ?? "the previous run"): failed \(signed(delta.failed)), median cents \(signed(delta.medianAbsCents))")
                                .font(.callout)
                        }
                        Text(report.engine)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                } else {
                    Text("No run yet. Start one from Test Runner.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            }
        }
    }

    private var builder: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Sources")
            GroupedCard {
                VStack(alignment: .leading, spacing: 10) {
                    field("Id", text: binding(\.draftID))
                    field("Title", text: binding(\.draftTitle))
                    field("Suite", text: binding(\.draftSuite))
                    field("Seed", text: binding(\.draftSeed))
                    field("Sample rate", text: binding(\.draftRate))
                    field("Duration", text: binding(\.draftDuration))
                    field("Kind", text: binding(\.draftKind))
                    field("Role", text: binding(\.draftRole))
                    field("Frequency", text: binding(\.draftFrequency))
                    field("Gain", text: binding(\.draftGain))
                    field("Formant", text: binding(\.draftFormant))
                    field("Cents offset", text: binding(\.draftCents))
                    field("Vibrato cents", text: binding(\.draftVibrato))
                    field("Noise color", text: binding(\.draftNoise))
                    field("SNR dB", text: binding(\.draftSnr))
                    HStack(spacing: 10) {
                        actionButton("Save") {
                            _ = store.saveDraft(root: root)
                        }
                        actionButton("Preview") {
                            Task { await store.preview(root: root, extraPath: model.loginShellPath) }
                        }
                    }
                    Text("Kind is sine, vocal, noise, or accompaniment. Role is vocal or instrument. Preview writes a WAV and plays it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .agentTarget("audio-builder")
        }
    }

    private var suites: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(AudioQaCatalog.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(section.title)
                    Text(section.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    GroupedCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(AudioQaCatalog.suites(in: section.id).enumerated()), id: \.element.id) { index, suite in
                                if index > 0 { CardDivider() }
                                Button {
                                    store.selectedSuite = suite.id
                                    store.scope = "suite"
                                    store.screen = .runner
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(suite.title).font(.headline)
                                        Text(suite.summary)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .agentTarget("audio-suites")
    }

    private var runner: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Run")
            GroupedCard {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Scope", selection: binding(\.scope)) {
                        Text("Suite").tag("suite")
                        Text("Scenario").tag("scenario")
                        Text("All").tag("all")
                    }
                    .pickerStyle(.segmented)
                    if store.scope == "suite" {
                        Picker("Section", selection: sectionBinding) {
                            ForEach(AudioQaCatalog.sections) { section in
                                Text(section.title).tag(section.id)
                            }
                        }
                        Picker("Suite", selection: binding(\.selectedSuite)) {
                            ForEach(AudioQaCatalog.suites(in: AudioQaCatalog.sectionID(for: store.selectedSuite))) { suite in
                                Text(suite.title).tag(suite.id)
                            }
                        }
                    }
                    if store.scope == "scenario" {
                        Picker("Scenario", selection: binding(\.selectedScenario)) {
                            ForEach(store.scenarioFiles, id: \.path) { file in
                                Text(file.lastPathComponent).tag(file.path)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        if store.running {
                            actionButton("Cancel", target: "audio-cancel") { store.cancel() }
                            ProgressView().controlSize(.small)
                        } else {
                            actionButton("Run", target: "audio-run") {
                                Task { await store.run(root: root, extraPath: model.loginShellPath) }
                            }
                        }
                    }
                    Text(store.log.isEmpty ? "Idle" : store.log)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
            }
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Scenarios")
            if let report = store.report {
                GroupedCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(report.passedCount)/\(report.total) passed")
                            .font(.headline)
                        ForEach(groupedResults(report.scenarios), id: \.id) { group in
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .padding(.top, 4)
                            ForEach(group.scenarios.filter { !$0.passed }) { scenario in
                                scenarioBlock(scenario, failed: true)
                            }
                            ForEach(group.scenarios.filter(\.passed)) { scenario in
                                scenarioBlock(scenario, failed: false)
                            }
                        }
                        if let compare = store.compare {
                            Text("Other run \(compare.id): failed \(compare.failed - report.failed) difference, median cents \(format(compare.summary.medianAbsCents - report.summary.medianAbsCents))")
                                .font(.callout)
                        }
                        if store.runFiles.count > 1 {
                            Picker("Compare", selection: Binding(
                                get: { "" },
                                set: { path in
                                    if !path.isEmpty {
                                        store.loadCompare(url: URL(fileURLWithPath: path))
                                    }
                                }
                            )) {
                                Text("Previous run").tag("")
                                ForEach(store.runFiles, id: \.path) { file in
                                    Text(file.lastPathComponent).tag(file.path)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
                .agentTarget("audio-results")
            } else {
                GroupedCard {
                    Text("Run a suite to see pitch, errors, and WAV files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
                .agentTarget("audio-results")
            }
        }
    }

    private func scenarioBlock(_ scenario: AudioQaScenarioFile, failed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(failed ? "Failed" : "Passed") · \(scenario.title)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(failed ? Color.red : Color.primary)
            if !scenario.failures.isEmpty {
                Text(scenario.failures.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Pitch median \(format(scenario.metrics.pitch.median)) · p95 \(format(scenario.metrics.pitch.p95)) · max \(format(scenario.metrics.pitch.max)) cents")
                .font(.caption)
            Text("Timing median \(format(scenario.metrics.timing.median)) ms · voice P/R \(format(scenario.metrics.voice.precision))/\(format(scenario.metrics.voice.recall)) · score \(format(scenario.metrics.scoreActual ?? 0)) vs \(format(scenario.metrics.scoreExpected ?? 0))")
                .font(.caption)
                .foregroundStyle(.secondary)
            AudioQaPitchChart(points: scenario.pitchSeries)
            AudioQaErrorChart(points: scenario.pitchSeries)
            HStack(spacing: 8) {
                if let wav = scenario.wavPath {
                    Button("Play") { store.play(url: URL(fileURLWithPath: wav)) }
                    Button("Save WAV") { store.export(url: URL(fileURLWithPath: wav)) }
                }
                if let reference = scenario.referencePath {
                    Button("Save reference") { store.export(url: URL(fileURLWithPath: reference)) }
                }
                Button("Save regression") {
                    Task {
                        await store.saveRegression(
                            root: root,
                            extraPath: model.loginShellPath,
                            scenario: scenario
                        )
                    }
                }
                .agentTarget("audio-save-\(scenario.id)")
            }
            .buttonStyle(.borderless)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title).frame(width: 120, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func actionButton(
        _ title: String,
        target: String = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule(style: .continuous).fill(LauncherTheme.tint(.audioQa)))
        }
        .buttonStyle(PressStyle())
        .agentTarget(target)
    }

    private var sectionBinding: Binding<String> {
        Binding(
            get: { AudioQaCatalog.sectionID(for: store.selectedSuite) },
            set: { section in
                guard AudioQaCatalog.sectionID(for: store.selectedSuite) != section,
                      let suite = AudioQaCatalog.suites(in: section).first else { return }
                store.selectedSuite = suite.id
            }
        )
    }

    private func groupedResults(_ scenarios: [AudioQaScenarioFile]) -> [(id: String, title: String, scenarios: [AudioQaScenarioFile])] {
        var grouped: [(id: String, title: String, scenarios: [AudioQaScenarioFile])] = []
        var placed = Set<String>()

        for section in AudioQaCatalog.sections {
            let rows = scenarios.filter { AudioQaCatalog.sectionID(for: $0.suite) == section.id }
            if rows.isEmpty { continue }
            grouped.append((section.id, section.title, rows))
            for row in rows { placed.insert(row.id) }
        }

        let leftovers = scenarios.filter { !placed.contains($0.id) }
        if !leftovers.isEmpty {
            grouped.append(("other", "Other", leftovers))
        }

        return grouped
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AudioQaStore, Value>) -> Binding<Value> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: { store[keyPath: keyPath] = $0 }
        )
    }

    private var root: URL {
        URL(fileURLWithPath: model.repoRoot)
    }

    private func reload() {
        guard model.rootIsValid else { return }
        store.reload(root: root)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func signed(_ value: Double) -> String {
        let number = format(value)
        return value > 0 ? "+\(number)" : number
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct AudioQaPitchChart: View {
    let points: [AudioQaPitchPoint]

    var body: some View {
        Canvas { context, size in
            let maxHz = max(
                points.compactMap(\.groundTruthHz).max() ?? 1,
                points.compactMap(\.detectedHz).max() ?? 1
            )
            let end = max(points.last?.timeSec ?? 1, 0.001)
            var reference = Path()
            var detected = Path()
            for point in points {
                let x = CGFloat(point.timeSec / end) * size.width
                if let hz = point.groundTruthHz {
                    let y = size.height - CGFloat(hz / maxHz) * (size.height - 6) - 3
                    append(point: CGPoint(x: x, y: y), to: &reference)
                }
                if let hz = point.detectedHz {
                    let y = size.height - CGFloat(hz / maxHz) * (size.height - 6) - 3
                    append(point: CGPoint(x: x, y: y), to: &detected)
                }
            }
            context.stroke(reference, with: .color(.secondary), lineWidth: 1.4)
            context.stroke(detected, with: .color(LauncherTheme.tint(.audioQa)), lineWidth: 1.4)
        }
        .frame(height: 120)
        .accessibilityLabel("Reference and detected pitch")
    }
}

private struct AudioQaErrorChart: View {
    let points: [AudioQaPitchPoint]

    var body: some View {
        Canvas { context, size in
            let errors = points.compactMap(\.errorCents).map(abs)
            let maxError = max(errors.max() ?? 1, 1)
            let end = max(points.last?.timeSec ?? 1, 0.001)
            var path = Path()
            for point in points {
                guard let error = point.errorCents else { continue }
                let x = CGFloat(point.timeSec / end) * size.width
                let y = size.height - CGFloat(abs(error) / maxError) * (size.height - 6) - 3
                append(point: CGPoint(x: x, y: y), to: &path)
            }
            context.stroke(path, with: .color(.red.opacity(0.8)), lineWidth: 1.2)
        }
        .frame(height: 72)
        .accessibilityLabel("Absolute pitch error")
    }
}

private func append(point: CGPoint, to path: inout Path) {
    if path.isEmpty {
        path.move(to: point)
    } else {
        path.addLine(to: point)
    }
}
