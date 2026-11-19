import SwiftUI

/// Shared status and install action for updates discovered by Sparkle.
struct InlineUpdateControls: View {
    let updates: AppUpdates

    var body: some View {
        if updates.availableVersion != nil || updates.progressDescription != nil || updates.message != nil {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    if let version = updates.availableVersion {
                        Text("AerialDrop \(version) is available")
                            .font(.callout.weight(.medium))
                    }
                    if let message = updates.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let progress = updates.progressDescription {
                    ProgressView {
                        Text(progress)
                    }
                    .controlSize(.small)
                } else if updates.availableVersion != nil {
                    Button("Install Update", action: updates.installAvailableUpdate)
                        .disabled(!updates.canInstallUpdate)
                        .help("Install the update and relaunch AerialDrop")
                        .accessibilityHint("Installs the update and relaunches AerialDrop when it is safe to do so.")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6))
            .accessibilityElement(children: .contain)
        }
    }
}
