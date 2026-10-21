import SwiftUI

/// Browsing is read-only. Continue captures one snapshot for a separate confirmation.
struct BackupChooser: View {
    @Environment(AppModel.self) private var model
    let onCancel: () -> Void
    let onChoose: (ManifestStore.BackupInfo) -> Void

    @State private var entries: [ManifestStore.BackupEntry] = []
    @State private var selectedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore Catalogue Backup")
                .font(.title2.bold())
            Text("Choose a saved catalogue, newest first. Backups restore catalogue entries, not deleted videos or thumbnails. Missing videos will appear as “Video missing”.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(selection: $selectedURL) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.date.formatted(date: .abbreviated, time: .standard))
                        Text("Before \(entry.operation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(entry.url)
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityLabel("Catalogue backups, newest first")
            .overlay {
                if entries.isEmpty, errorMessage == nil {
                    ContentUnavailableView("No Backups Found", systemImage: "clock.arrow.circlepath", description: Text("AerialDrop creates a backup before each catalogue change."))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Reload Backups", systemImage: "arrow.clockwise", action: reload)
                    .disabled(model.isWorking)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Continue…", action: choose)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking || selectedURL == nil)
            }
        }
        .padding(24)
        .frame(width: 560, height: 500)
        .onAppear(perform: reload)
    }

    private func reload() {
        do {
            entries = try model.backupHistory()
            if !entries.contains(where: { $0.url == selectedURL }) {
                selectedURL = entries.first?.url
            }
            errorMessage = nil
        } catch {
            entries = []
            selectedURL = nil
            report("Couldn’t read the backups. \(error.localizedDescription) Reload Backups to try again.")
        }
    }

    private func choose() {
        guard !model.isWorking, let entry = entries.first(where: { $0.url == selectedURL }) else { return }
        let snapshot = entry.snapshot()
        guard snapshot.content != nil else {
            report("This backup couldn’t be read. Reload Backups, then choose an available backup.")
            return
        }
        onChoose(snapshot)
    }

    private func report(_ message: String) {
        errorMessage = message
        AccessibilityNotification.Announcement(message).post()
    }
}
