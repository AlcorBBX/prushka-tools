import SwiftUI

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.4)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}

struct GroupedCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LauncherTheme.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LauncherTheme.stroke(scheme), lineWidth: 1)
        }
    }
}

struct ModeChip: View {
    var title: String

    private var tint: Color {
        switch title {
        case "Prod": Color(red: 0.93, green: 0.55, blue: 0.28)
        case "Memory": LauncherTheme.tint(.settings)
        case "Fix": Color(red: 0.20, green: 0.72, blue: 0.48)
        case "Check": Color(red: 0.22, green: 0.48, blue: 0.98)
        case "Hook": Color(red: 0.58, green: 0.34, blue: 0.96)
        case "Run": Color(red: 0.16, green: 0.70, blue: 0.78)
        default: LauncherTheme.tint(.services)
        }
    }

    var body: some View {
        StatusChip(title: title, tint: tint)
    }
}

struct StatusChip: View {
    var title: String
    var tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.16)))
    }
}

struct CardDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
            .opacity(0.85)
    }
}

struct StatusDot: View {
    var running: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(running ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
            .scaleEffect(running && pulse ? 1.35 : 1)
            .opacity(running && pulse ? 0.45 : 1)
            .onAppear { animate() }
            .onChange(of: running) { _, _ in animate() }
            .accessibilityLabel(running ? "Running" : "Stopped")
    }

    private func animate() {
        pulse = false
        guard running, !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .textSelection(.enabled)
    }
}

struct NavIcon: View {
    let section: AppSection

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LauncherTheme.tint(section).gradient)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
    }
}

struct SidebarColumn: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var showsLabels: Bool
    @State private var hovered: AppSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AppSection.allCases) { section in
                Button {
                    select(section)
                } label: {
                    HStack(spacing: 10) {
                        NavIcon(section: section)
                        if showsLabels {
                            Text(section.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, showsLabels ? 8 : 6)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(background(for: section))
                    }
                    .overlay {
                        if model.section == section {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(LauncherTheme.tint(section).opacity(0.28), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(PressStyle())
                .help(section.title)
                .onHover { hovering in
                    hovered = hovering ? section : (hovered == section ? nil : hovered)
                }
                .keyboardShortcut(shortcut(for: section), modifiers: [.command])
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(width: showsLabels ? 232 : 52)
        .background(LauncherTheme.sidebar(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LauncherTheme.stroke(scheme), lineWidth: 1)
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 8, y: 2)
    }

    private func background(for section: AppSection) -> Color {
        if model.section == section {
            return LauncherTheme.tint(section).opacity(0.18)
        }
        if hovered == section {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }

    private func select(_ section: AppSection) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
            model.section = section
        }
    }

    private func shortcut(for section: AppSection) -> KeyEquivalent {
        switch section {
        case .services: "1"
        case .checks: "2"
        case .tools: "3"
        case .logs: "4"
        case .settings: "5"
        }
    }
}

struct SectionChips: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                            model.section = section
                        }
                    } label: {
                        HStack(spacing: 8) {
                            NavIcon(section: section)
                            Text(section.title)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            Capsule(style: .continuous)
                                .fill(
                                    model.section == section
                                        ? LauncherTheme.tint(section).opacity(0.18)
                                        : Color.primary.opacity(0.05)
                                )
                        }
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }
}
