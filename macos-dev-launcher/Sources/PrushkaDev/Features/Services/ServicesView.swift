import SwiftUI

struct ServicesView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let statusError = model.statusError {
                ErrorBanner(message: statusError)
            }
            if let actionError = model.actionError {
                ErrorBanner(message: actionError)
            }
            if !model.rootIsValid {
                missingRoot
            } else {
                ForEach(ServiceGroup.allCases) { group in
                    let families = ServiceCatalog.families(in: group)
                    if !families.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(group.title)
                            GroupedCard {
                                ForEach(Array(families.enumerated()), id: \.element.id) { index, family in
                                    if index > 0 {
                                        CardDivider()
                                    }
                                    ServiceFamilyRow(family: family)
                                }
                            }
                        }
                    }
                }
                actions
            }
        }
    }

    private var missingRoot: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Repository")
            GroupedCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Point Settings at the Prushka checkout. Status and start buttons use that folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                    Button("Open Settings") {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                            model.section = .settings
                        }
                    }
                    .buttonStyle(PressStyle())
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Session")
            HStack(alignment: .center, spacing: 10) {
                Button {
                    Task { await model.startDefault() }
                } label: {
                    Label("Start default", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background {
                            Capsule(style: .continuous)
                                .fill(LauncherTheme.tint(.services))
                        }
                }
                .buttonStyle(PressStyle())
                .disabled(model.isBusy("bundle"))

                Button {
                    Task { await model.stopAll() }
                } label: {
                    Label("Stop all", systemImage: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.red.opacity(0.95))
                        .background {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(PressStyle())
                .disabled(model.isBusy("bundle"))

                if model.isBusy("bundle") {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 2)
                }

                Spacer(minLength: 8)

                Text(model.checkedLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            Text("Default starts web and stems (dev). Prod builds first, then serves. Click a row for live logs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

private struct ServiceFamilyRow: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let family: ServiceFamily

    @State private var selectedVariantID: String = ""

    private var selectedVariant: ServiceVariant {
        family.variant(id: selectedVariantID.isEmpty ? preferredVariantID : selectedVariantID)
            ?? family.variants[0]
    }

    private var preferredVariantID: String {
        if let running = family.variants.first(where: { model.unit(id: $0.id)?.isRunning == true }) {
            return running.id
        }
        return family.defaultVariantID
    }

    private var unitID: String { selectedVariant.id }

    private var unit: UnitStatus? { model.unit(id: unitID) }

    private var running: Bool { unit?.isRunning == true }

    private var log: ServiceLogState { model.serviceLog(for: unitID) }

    private var isLogExpanded: Bool {
        model.expandedServiceFamilyID == family.id
    }

    private var showsCollapsedPreview: Bool {
        running && !log.lastLine.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(LauncherMotion.easeOut(reduceMotion: reduceMotion)) {
                        model.toggleServiceExpansion(family.id)
                    }
                    if model.expandedServiceFamilyID == family.id {
                        model.refreshServiceLog(unitID: unitID)
                    }
                } label: {
                    headerMain
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                ExpandingModePicker(
                    options: family.variants.map(\.modeOption),
                    selection: selectedVariantBinding
                )

                controls
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if !isLogExpanded, showsCollapsedPreview {
                Button {
                    withAnimation(LauncherMotion.easeOut(reduceMotion: reduceMotion)) {
                        model.toggleServiceExpansion(family.id)
                    }
                    model.refreshServiceLog(unitID: unitID)
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
                selectedVariantID = preferredVariantID
            }
            if running {
                model.refreshServiceLog(unitID: unitID)
            }
        }
        .onChange(of: selectedVariantID) { _, newValue in
            guard !newValue.isEmpty else { return }
            model.refreshServiceLog(unitID: newValue)
            if isLogExpanded {
                model.selectLog(newValue)
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
            get: { selectedVariantID.isEmpty ? preferredVariantID : selectedVariantID },
            set: { selectedVariantID = $0 }
        )
    }

    private var headerMain: some View {
        HStack(alignment: .center, spacing: 10) {
            StatusDot(running: running)

            VStack(alignment: .leading, spacing: 4) {
                Text(family.title)
                    .font(.system(size: 15, weight: .medium))
                statusChips
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusChips: some View {
        HStack(spacing: 5) {
            StatusChip(
                title: running ? "Running" : "Stopped",
                tint: running ? Color.green : Color.secondary
            )
            if unit?.showsExternalBadge == true {
                StatusChip(
                    title: unit?.source == "mixed" ? "Mixed" : "External",
                    tint: .orange
                )
            }
            if running, unit?.health == "fail" {
                StatusChip(title: "Unhealthy", tint: .orange)
            }
            if let pid = unit?.pid, running {
                Text("pid \(pid)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if model.isBusy(unitID) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28)
            } else if running {
                rowButton("Stop", role: .stop) {
                    Task { await model.stop(unitID: unitID) }
                }
            } else {
                rowButton("Start", role: .start) {
                    Task { await model.start(unitID: unitID) }
                }
            }
            if let url = model.openTarget(for: unitID), running {
                rowButton("Open", role: .open) {
                    model.open(urlString: url)
                }
            }
        }
        .layoutPriority(1)
    }

    private enum RowRole {
        case start
        case stop
        case open
    }

    private func rowButton(_ title: String, role: RowRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(role == .stop ? Color.red : LauncherTheme.tint(.services))
        }
        .buttonStyle(PressStyle())
        .disabled(model.isBusy(unitID) && role != .open)
    }

    private var collapsedPreview: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(running ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(log.lastLine)
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

    private var expandedLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(running ? "Live log · \(selectedVariant.chip)" : "Log · \(selectedVariant.chip)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if running, !log.lastLine.isEmpty {
                    Text(log.lastLine)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(maxWidth: 220, alignment: .trailing)
                }
            }
            ConsolePane(
                source: log,
                revision: log.logRevision,
                isLive: running,
                emptyPlaceholder: "No log yet. Start from the launcher to capture output."
            )
            .frame(minHeight: 160, maxHeight: 280)
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LauncherTheme.field(scheme))
            }
        }
        .padding(.top, 2)
        .onAppear {
            model.selectLog(unitID)
            model.refreshServiceLog(unitID: unitID)
        }
    }
}
