import SwiftUI

public struct RootView: View {
    @Environment(LauncherModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 1040

    public init() {}

    public var body: some View {
        let layout = ShellLayout(width: width)
        VStack(alignment: .leading, spacing: 22) {
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
    }

    private var detail: some View {
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
        case .settings:
            SettingsView()
        }
    }
}
