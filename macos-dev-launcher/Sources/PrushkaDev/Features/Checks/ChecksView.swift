import SwiftUI

struct ChecksView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let actionError = model.actionError {
                ErrorBanner(message: actionError)
            }
            if !model.rootIsValid {
                GroupedCard {
                    Text("Point Settings at the Prushka checkout. Checks run pnpm scripts from front/.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            } else {
                ForEach(QualityGroup.allCases) { group in
                    let families = QualityCatalog.families(in: group)
                    if !families.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(group.title)
                            GroupedCard {
                                ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                                    if index > 0 {
                                        CardDivider()
                                    }
                                    QualityFamilyRow(family: family)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Don't animate expand/collapse of log panes — animating large console layout freezes the UI.
    }
}

private struct QualityFamilyRow: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let family: QualityFamily

    @State private var selectedVariantID: String = ""

    private var selectedVariant: QualityVariant {
        family.variant(id: selectedVariantID.isEmpty ? family.defaultVariantID : selectedVariantID)
            ?? family.variants[0]
    }

    private var selectedJob: QualityJob {
        family.job(variantID: selectedVariant.id)
            ?? QualityJob(
                id: selectedVariant.id,
                group: family.group,
                title: family.title,
                summary: selectedVariant.summary,
                chip: selectedVariant.chip,
                cwd: selectedVariant.cwd,
                command: selectedVariant.command
            )
    }

    private var run: QualityRunState {
        model.qualityRun(for: selectedVariant.id)
    }

    private var isLogExpanded: Bool {
        model.expandedQualityJobID == family.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(LauncherMotion.easeOut(reduceMotion: reduceMotion)) {
                        model.toggleQualityExpansion(family.id)
                    }
                } label: {
                    headerMain
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                ExpandingModePicker(
                    options: family.variants.map { ModeOption(id: $0.id, chip: $0.chip) },
                    selection: selectedVariantBinding
                )

                controls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLogExpanded, showsCollapsedPreview {
                Button {
                    withAnimation(LauncherMotion.easeOut(reduceMotion: reduceMotion)) {
                        model.toggleQualityExpansion(family.id)
                    }
                } label: {
                    collapsedPreview
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(logTransition)
            }

            if isLogExpanded {
                expandedLog
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(logTransition)
            }
        }
        .animation(LauncherMotion.easeOut(reduceMotion: reduceMotion), value: isLogExpanded)
        .onAppear {
            if selectedVariantID.isEmpty {
                selectedVariantID = family.defaultVariantID
            }
        }
    }

    private var logTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }

    private var selectedVariantBinding: Binding<String> {
        Binding(
            get: { selectedVariantID.isEmpty ? family.defaultVariantID : selectedVariantID },
            set: { selectedVariantID = $0 }
        )
    }

    private var showsCollapsedPreview: Bool {
        run.outcome != .idle && !run.lastLine.isEmpty
    }

    private var headerMain: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(family.title)
                        .font(.system(size: 15, weight: .medium))
                    outcomeChip
                }
                Text(selectedVariant.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var outcomeChip: some View {
        switch run.outcome {
        case .idle:
            EmptyView()
        case .running:
            StatusChip(title: "Running", tint: LauncherTheme.tint(.checks))
        case .succeeded:
            StatusChip(title: "OK", tint: .green)
        case .failed:
            StatusChip(title: "Failed", tint: .red)
        case .cancelled:
            StatusChip(title: "Stopped", tint: .orange)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if run.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("Stop") {
                    model.cancelQuality(selectedVariant.id)
                }
                .buttonStyle(PressStyle())
                .foregroundStyle(.red)
                .font(.system(size: 13, weight: .semibold))
            } else {
                Button {
                    Task { await model.runQuality(selectedJob) }
                } label: {
                    Text("Run")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule(style: .continuous).fill(LauncherTheme.tint(.checks)))
                }
                .buttonStyle(PressStyle())
            }
        }
    }

    private var collapsedPreview: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(previewTint)
                .frame(width: 6, height: 6)
            Text(run.lastLine)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LauncherTheme.field(scheme))
        }
    }

    private var previewTint: Color {
        switch run.outcome {
        case .running: LauncherTheme.tint(.checks)
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .orange
        case .idle: .secondary
        }
    }

    private var expandedLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(logTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if run.isRunning {
                    Text(run.lastLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .trailing)
                } else if let code = run.exitCode {
                    Text("exit \(code)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            ConsolePane(
                source: run,
                revision: run.logRevision,
                isLive: run.isRunning
            )
            .frame(minHeight: 160, maxHeight: 280)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LauncherTheme.field(scheme))
            }
        }
        .padding(.top, 2)
    }

    private var logTitle: String {
        switch run.outcome {
        case .running: "Live output · \(selectedVariant.chip)"
        case .succeeded: "Succeeded · \(selectedVariant.chip)"
        case .failed: "Failed · \(selectedVariant.chip)"
        case .cancelled: "Stopped · \(selectedVariant.chip)"
        case .idle: "Output"
        }
    }
}

