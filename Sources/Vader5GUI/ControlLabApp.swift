import SwiftUI

@main
struct ControlLabApp: App {
    @StateObject private var model = BridgeViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
