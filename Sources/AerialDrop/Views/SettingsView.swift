import SwiftUI

struct SettingsView: View {
    let updates: AppUpdates
    @AppStorage(AppPreferences.setWallpaperAfterImportKey) private var setWallpaperAfterImport = true

    var body: some View {
        Form {
            Toggle("Set as wallpaper after importing", isOn: $setWallpaperAfterImport)
                .accessibilityHint("Automatically applies a successfully imported AerialDrop video everywhere.")

            Text("When enabled, AerialDrop applies the new Aerial across all Spaces and displays after a successful import. Turn this off to add videos without changing your current wallpaper.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if updates.isConfigured {
                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: updates.setAutomaticallyChecksForUpdates
                    ))
                    CheckForUpdatesButton(updates: updates)
                }
            }

            // Shown regardless of bundling: unbundled swift-run launches have
            // no About panel version to consult.
            Text("AerialDrop \(AppVersion.shortVersion) (\(AppVersion.buildNumber))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}

struct CheckForUpdatesButton: View {
    let updates: AppUpdates

    var body: some View {
        Button("Check for Updates…", action: updates.checkForUpdates)
            .disabled(!updates.canCheckForUpdates)
    }
}
