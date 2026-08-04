import SwiftUI

@main
struct AerialDropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Native Setup") {
                Button("Finish Native Setup") {
                    model.finishNativeSetup()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.wallpapers.isEmpty || model.isWorking)
            }

            CommandMenu("Maintenance") {
                Button("Validate Current Catalogue") {
                    model.validateCatalogue()
                }

                Button("Open Aerial Storage Folder") {
                    model.openStorageFolder()
                }
            }
        }
    }
}
