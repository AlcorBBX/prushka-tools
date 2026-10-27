import SwiftUI

struct LogsView: View {
    @Environment(LauncherModel.self) private var model

    private var unitIDs: [String] {
        let fromStatus = model.units.map(\.id)
        if !fromStatus.isEmpty {
            return fromStatus
        }
        return ServiceGroup.allCases.flatMap(\.unitIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Unit")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(unitIDs, id: \.self) { id in
                            Button {
                                model.selectLog(id)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(UnitFace.title(for: id))
                                    if !UnitFace.chip(for: id).isEmpty {
                                        Text(UnitFace.chip(for: id))
                                            .font(.system(size: 10, weight: .semibold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                Capsule(style: .continuous).fill(
                                                    model.selectedLogID == id
                                                        ? Color.white.opacity(0.22)
                                                        : Color.primary.opacity(0.08)
                                                )
                                            )
                                    }
                                }
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(model.selectedLogID == id ? Color.white : Color.primary)
                                    .background {
                                        Capsule(style: .continuous)
                                            .fill(
                                                model.selectedLogID == id
                                                    ? LauncherTheme.tint(.logs)
                                                    : Color.primary.opacity(0.06)
                                            )
                                    }
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Tail")
                GroupedCard {
                    ScrollView {
                        Text(bodyText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(model.logText.isEmpty ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(14)
                    }
                    .frame(minHeight: 320)
                }
                Text("This file is written when the unit is started from the launcher. A process started in a terminal still shows up under Services, but its own terminal keeps the live log.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var bodyText: String {
        if model.logText.isEmpty {
            return "No log yet for \(UnitFace.title(for: model.selectedLogID))."
        }
        return model.logText
    }
}
