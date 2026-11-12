import PrushkaDevCore
import SwiftUI

@main
struct PrushkaDevApp: App {
    @State private var model = LauncherModel()
    @State private var audio = AudioQaStore()
    @State private var agent = AgentCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(audio)
                .environment(agent)
                .task {
                    await model.bootstrap()
                    await agent.start(model: model, audio: audio)
                }
                .frame(minWidth: 520, minHeight: 540)
        }
        .defaultSize(width: 1040, height: 740)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
    }
}
