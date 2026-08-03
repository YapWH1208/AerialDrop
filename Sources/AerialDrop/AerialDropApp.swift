import SwiftUI

@main
struct AerialDropApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Native Setup") {
                Button("Finish Native Setup") {
                    model.finishNativeSetup()
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(model.wallpapers.isEmpty || model.isWorking)

                Button("Restore Latest Selection Backup") {
                    model.restoreLatestSelectionBackup()
                }
                .disabled(model.isWorking)
            }

            CommandMenu("Maintenance") {
                Button("Repair Catalogue Registration") {
                    model.repairCatalogueRegistration()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

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
