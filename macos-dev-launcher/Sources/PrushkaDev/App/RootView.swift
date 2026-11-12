import SwiftUI

public struct RootView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(AgentCoordinator.self) private var agent
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 1040

    public init() {}

    public var body: some View {
        let layout = ShellLayout(width: width)
        VStack(alignment: .leading, spacing: 22) {
            if agent.controlling {
                AgentControlBanner()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            PageHeader(title: model.section.title, subtitle: model.section.subtitle)
            switch layout {
            case .split:
                HStack(alignment: .top, spacing: 28) {
                    SidebarColumn(showsLabels: true)
                    detail
                }
            case .rail:
                HStack(alignment: .top, spacing: 20) {
                    SidebarColumn(showsLabels: false)
                    detail
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 16) {
                    SectionChips()
                    detail
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in
                        width = newValue
                    }
            }
        }
        .background(LauncherTheme.canvas(scheme).ignoresSafeArea())
        .background(WindowChromeBinder(scheme: scheme))
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88), value: layout)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: model.section)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: agent.controlling)
    }

    private var detail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    detailContent
                        .id(model.section)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: agent.cursor?.token) { _, token in
                guard let token, let target = agent.cursor?.targetID, !target.isEmpty else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(90))
                    guard agent.cursor?.token == token else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.section {
        case .services:
            ServicesView()
        case .checks:
            ChecksView()
        case .git:
            GitView()
        case .tools:
            ToolsView()
        case .logs:
            LogsView()
        case .audioQa:
            AudioQaView()
        case .settings:
            SettingsView()
        }
    }
}
