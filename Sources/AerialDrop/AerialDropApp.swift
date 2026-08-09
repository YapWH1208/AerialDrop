import SwiftUI

@main
struct AerialDropApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AerialDrop") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Video…") {
                    model.showingFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }

        Window("Preview & Adjust", id: "import-preview") {
            ImportPreviewWindow()
                .environment(model)
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
    }
}
