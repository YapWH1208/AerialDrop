import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.setWallpaperAfterImportKey) private var setWallpaperAfterImport = true

    var body: some View {
        Form {
            Toggle("Set as wallpaper after importing", isOn: $setWallpaperAfterImport)
                .accessibilityHint("Automatically applies a successfully imported AerialDrop video everywhere.")

            Text("When enabled, AerialDrop applies the new Aerial across all Spaces and displays after a successful import. Turn this off to add videos without changing your current wallpaper.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding()
    }
}
