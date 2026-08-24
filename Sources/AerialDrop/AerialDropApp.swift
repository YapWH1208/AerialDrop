import AppKit
import SwiftUI

@main
struct AerialDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("AerialDrop") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Choose Video…") {
                    model.showingFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isWorking || model.catalogueState != .ready)
            }
            CommandGroup(replacing: .help) {
                Button("AerialDrop Website") { helpURLs.open(helpURLs.website) }
                Button("Frequently Asked Questions") { helpURLs.open(helpURLs.faq) }
                Button("Release Notes") { helpURLs.open(helpURLs.releaseNotes) }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Intercepts quit while an import is running so a long encode is not
/// discarded silently (any partial files are cleaned on the next launch).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Documentation destinations surfaced from the app's Help menu.
    enum helpURLs {
        static let website = URL(string: "https://yapwh1208.github.io/AerialDrop/")!
        static let faq = URL(string: "https://yapwh1208.github.io/AerialDrop/#faq")!
        static let releaseNotes = URL(string: "https://github.com/YapWH1208/AerialDrop/releases")!

        static func open(_ url: URL) {
            _ = NSWorkspace.shared.open(url)
        }
    }

    weak var model: AppModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model,
              model.isWorking,
              model.stage != .idle,
              model.stage != .finished else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Import in Progress"
        alert.informativeText = "AerialDrop is still importing. Quitting now will discard the encode. You can cancel the import safely from the toolbar instead."
        alert.addButton(withTitle: "Keep Importing")
        alert.addButton(withTitle: "Quit Anyway")
        alert.alertStyle = .warning
        let response = alert.runModal()
        return response == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
