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
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(group.title)
                        GroupedCard {
                            let ids = group.unitIDs
                            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                                if index > 0 {
                                    CardDivider()
                                }
                                ServiceRow(unitID: id)
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
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Session")
            GroupedCard {
                HStack(spacing: 12) {
                    Button {
                        Task { await model.startDefault() }
                    } label: {
                        actionLabel("Start default", systemImage: "play.fill", prominent: true)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.isBusy("bundle"))

                    Button {
                        Task { await model.stopAll() }
                    } label: {
                        actionLabel("Stop all", systemImage: "stop.fill", prominent: false)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(model.isBusy("bundle"))

                    Spacer(minLength: 0)
                    if model.isBusy("bundle") {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            Text("Default starts web dev and stems dev. Prod rows build first, then serve the bundle. Open uses the same localhost address Vite prints. Last check \(model.checkedLabel).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func actionLabel(_ title: String, systemImage: String, prominent: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? LauncherTheme.tint(.services) : Color.primary.opacity(0.08))
            }
    }
}

private struct ServiceRow: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let unitID: String

    var body: some View {
        let unit = model.unit(id: unitID)
        let running = unit?.isRunning == true
        ViewThatFits(in: .horizontal) {
            wide(unit: unit, running: running)
            stacked(unit: unit, running: running)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func wide(unit: UnitStatus?, running: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            identity(unit: unit, running: running)
            Spacer(minLength: 12)
            controls(unit: unit, running: running)
        }
    }

    private func stacked(unit: UnitStatus?, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            identity(unit: unit, running: running)
            HStack {
                Spacer(minLength: 0)
                controls(unit: unit, running: running)
            }
        }
    }

    private func identity(unit: UnitStatus?, running: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            StatusDot(running: running)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(UnitFace.title(for: unitID))
                        .font(.system(size: 15, weight: .medium))
                    if !UnitFace.chip(for: unitID).isEmpty {
                        ModeChip(title: UnitFace.chip(for: unitID))
                    }
                }
                statusChips(unit: unit, running: running)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusChips(unit: UnitStatus?, running: Bool) -> some View {
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

    private func controls(unit: UnitStatus?, running: Bool) -> some View {
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
            rowButton("Logs", role: .logs) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    model.selectLog(unitID)
                    model.section = .logs
                }
            }
        }
        .layoutPriority(1)
    }

    private enum RowRole {
        case start
        case stop
        case open
        case logs
    }

    private func rowButton(_ title: String, role: RowRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(role == .stop ? Color.red : (role == .logs ? Color.secondary : LauncherTheme.tint(.services)))
        }
        .buttonStyle(PressStyle())
        .disabled(model.isBusy(unitID) && role != .open && role != .logs)
    }
}
