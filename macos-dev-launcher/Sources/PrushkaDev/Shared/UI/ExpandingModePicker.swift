import SwiftUI

struct ModeOption: Identifiable, Equatable, Sendable {
    let id: String
    let chip: String
}

/// Compact mode switch: one chip by default, expands on click, collapses after the cursor leaves.
struct ExpandingModePicker: View {
    let options: [ModeOption]
    @Binding var selection: String
    var chipColor: (String) -> Color = ModeChipColor.tint

    @State private var isOpen = false
    @State private var collapseTask: Task<Void, Never>?
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private let controlHeight: CGFloat = 24

    private var motion: Animation? {
        LauncherMotion.easeOut(reduceMotion: reduceMotion)
    }

    private var selected: ModeOption {
        options.first { $0.id == selection } ?? options[0]
    }

    var body: some View {
        Group {
            if options.count <= 1 {
                loneChip(selected)
            } else {
                interactive
            }
        }
        .frame(height: controlHeight)
        .onDisappear {
            cancelCollapse()
        }
    }

    private var interactive: some View {
        ZStack(alignment: .trailing) {
            if isOpen {
                expandedTrack
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing))
                        )
                    )
            } else {
                collapsedChip
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)),
                            removal: .opacity.combined(with: .scale(scale: 0.92, anchor: .trailing))
                        )
                    )
            }
        }
        .frame(height: controlHeight, alignment: .trailing)
        .clipped()
        .onHover { hovering in
            if hovering {
                cancelCollapse()
            } else if isOpen {
                scheduleCollapse()
            }
        }
    }

    private var collapsedChip: some View {
        Button {
            cancelCollapse()
            withAnimation(motion) { isOpen = true }
        } label: {
            loneChip(selected)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityLabel("Mode \(selected.chip), expand")
    }

    private var expandedTrack: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let active = selection == option.id
                Button {
                    withAnimation(motion) {
                        selection = option.id
                    }
                } label: {
                    Text(option.chip)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            if active {
                                Capsule(style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                    .shadow(
                                        color: .black.opacity(scheme == .dark ? 0.25 : 0.06),
                                        radius: 1,
                                        y: 0.5
                                    )
                                    .matchedGeometryEffect(id: "mode-pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityLabel(option.chip)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
        }
    }

    private func loneChip(_ option: ModeOption) -> some View {
        let tint = chipColor(option.chip)
        return Text(option.chip)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.16))
            }
    }

    private func scheduleCollapse() {
        cancelCollapse()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            withAnimation(motion) { isOpen = false }
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }
}

enum ModeChipColor {
    static func tint(_ title: String) -> Color {
        switch title {
        case "Fix": Color(red: 0.20, green: 0.72, blue: 0.48)
        case "Check": Color(red: 0.22, green: 0.48, blue: 0.98)
        case "Coverage": Color(red: 0.93, green: 0.55, blue: 0.28)
        case "Commit": Color(red: 0.58, green: 0.34, blue: 0.96)
        case "Push": Color(red: 0.94, green: 0.38, blue: 0.30)
        case "Dev": Color(red: 0.22, green: 0.48, blue: 0.98)
        case "Prod": Color(red: 0.93, green: 0.55, blue: 0.28)
        case "Memory": Color(red: 0.58, green: 0.34, blue: 0.96)
        default: LauncherTheme.tint(.services)
        }
    }
}
