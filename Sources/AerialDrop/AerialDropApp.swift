import AppKit
import SwiftUI

@main
struct AerialDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
    @State private var updates: AppUpdates

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _updates = State(initialValue: AppUpdates(model: model))
    }

    var body: some Scene {
        WindowGroup("AerialDrop") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    appDelegate.model = model
                    appDelegate.updates = updates
                    updates.start()
                }
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if updates.isConfigured {
                    Button("Check for Updates…", action: updates.checkForUpdates)
                        .disabled(!updates.canCheckForUpdates)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Choose Video…") {
                    model.showingFileImporter = true
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(model.isWorking || model.catalogueState != .ready)
            }
            CommandGroup(replacing: .help) {
                Button("AerialDrop Website") { HelpURLs.open(HelpURLs.website) }
                Button("Frequently Asked Questions") { HelpURLs.open(HelpURLs.faq) }
                Button("Release Notes") { HelpURLs.open(HelpURLs.releaseNotes) }
            }
        }

        Settings {
            SettingsView(updates: updates)
        }
    }
}

/// Documentation destinations surfaced from the app's Help menu.
private enum HelpURLs {
    static let website = URL(string: "https://yapwh1208.github.io/AerialDrop/")!
    static let faq = URL(string: "https://yapwh1208.github.io/AerialDrop/#faq")!
    static let releaseNotes = URL(string: "https://github.com/YapWH1208/AerialDrop/releases")!

    static func open(_ url: URL) {
        _ = NSWorkspace.shared.open(url)
    }
}

/// Intercepts quit while an import is running so a long encode is not
/// discarded silently (any partial files are cleaned on the next launch).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    weak var updates: AppUpdates?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A new operation can start after Sparkle has requested installation.
        if let updates, updates.isInstallingUpdate,
           updates.deferRelaunchIfBusy({ sender.reply(toApplicationShouldTerminate: true) }) {
            return .terminateLater
        }

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
