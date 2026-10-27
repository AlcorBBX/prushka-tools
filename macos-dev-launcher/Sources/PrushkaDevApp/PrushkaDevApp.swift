import PrushkaDevCore
import SwiftUI

@main
struct PrushkaDevApp: App {
    @State private var model = LauncherModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
                .frame(minWidth: 520, minHeight: 540)
        }
        .defaultSize(width: 1040, height: 740)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}
