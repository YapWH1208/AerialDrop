import SwiftUI

struct CatalogueAccessView: View {
    let state: CatalogueState
    let onOpenSettings: () -> Void
    let onCheckAgain: () -> Void

    @ViewBuilder
    var body: some View {
        switch state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Checking the Aerial catalogue…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)

        case .unavailable(let message):
            ContentUnavailableView {
                Label("Set Up Apple Aerials", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Open Wallpaper Settings", systemImage: "photo", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)

                Button("Check Again", systemImage: "arrow.clockwise", action: onCheckAgain)
            }

        case .ready:
            EmptyView()
        }
    }
}
