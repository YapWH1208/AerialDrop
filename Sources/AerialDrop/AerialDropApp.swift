import SwiftUI

@main
struct AerialDropApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .windowBackgroundDragBehavior(.enabled)
    }
}
