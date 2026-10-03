import AppKit
import SwiftUI

struct DayNightWallpaperSection: View {
    @Environment(AppModel.self) private var model
    @Binding private var isExpanded: Bool

    init(isExpanded: Binding<Bool>) {
        _isExpanded = isExpanded
    }

    var body: some View {
        @Bindable var model = model

        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choosing videos only saves this draft. Apply updates every Space and display. macOS then switches between Day and Night using the sun’s position, even after AerialDrop quits.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    roleEditor(
                        title: "Day",
                        selection: $model.dayWallpaperID,
                        selectedID: model.dayWallpaperID
                    )
                    roleEditor(
                        title: "Night",
                        selection: $model.nightWallpaperID,
                        selectedID: model.nightWallpaperID
                    )
                }

                if let reason = model.dayNightUnavailableReason {
                    inlineMessage(reason, systemImage: "exclamationmark.triangle")
                } else if let blocker = model.dayNightApplyBlockerMessage {
                    inlineMessage(blocker, systemImage: "exclamationmark.circle")
                }

                HStack {
                    Spacer()

                    Button("Apply Day/Night Wallpaper") {
                        model.applyDayNightWallpaper()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canApplyDayNightWallpaper || model.isWorking)
                    .help(applyHelp)
                }
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Day/Night Wallpaper")
                    .font(.headline)
                Text(model.dayNightStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .disabled(model.isWorking)
        .padding(.horizontal, 24)
        .onAppear {
            if shouldExpand { isExpanded = true }
        }
        .onChange(of: shouldExpand) { _, expand in
            if expand { isExpanded = true }
        }
    }

    private var shouldExpand: Bool {
        model.dayNightDraft.dayAssetID != nil
            || model.dayNightDraft.nightAssetID != nil
            || model.registeredDayNightPair != nil
            || model.isDayNightRecoveryPending
    }

    private var applyHelp: String {
        if model.isWorking {
            return "Wait for the current operation to finish"
        }
        if let reason = model.dayNightUnavailableReason {
            return reason
        }
        if let blocker = model.dayNightApplyBlockerMessage {
            return blocker
        }
        return "Apply and activate this Day/Night wallpaper across all Spaces and displays"
    }

    private func roleEditor(
        title: String,
        selection: Binding<String?>,
        selectedID: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: selection) {
                Text("Choose Wallpaper").tag(nil as String?)

                if let selectedID, wallpaper(for: selectedID) == nil {
                    Divider()
                    Text("Wallpaper Missing").tag(Optional(selectedID))
                }

                if !model.wallpapers.isEmpty {
                    Divider()
                    ForEach(model.wallpapers) { wallpaper in
                        Text(wallpaper.title).tag(Optional(wallpaper.id))
                    }
                }
            }
            .pickerStyle(.menu)
            .disabled(model.dayNightUnavailableReason != nil || model.isWorking)
            .accessibilityHint("Choose an imported wallpaper for the \(title.lowercased()) role.")

            selectedWallpaperSummary(selectedID: selectedID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func selectedWallpaperSummary(selectedID: String?) -> some View {
        if let selectedID, let wallpaper = wallpaper(for: selectedID) {
            HStack(alignment: .top, spacing: 9) {
                DayNightThumbnail(wallpaper: wallpaper)

                VStack(alignment: .leading, spacing: 3) {
                    Text(wallpaper.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(wallpaper.title)

                    if !wallpaper.videoExists {
                        missingFileLabel("Video missing")
                    }
                    if !wallpaper.thumbnailExists {
                        missingFileLabel("Thumbnail missing")
                    }
                }

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else if selectedID != nil {
            Label("Wallpaper Missing", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Text("No wallpaper selected")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private func wallpaper(for id: String) -> ManagedWallpaper? {
        model.wallpapers.first { $0.id == id }
    }

    private func missingFileLabel(_ title: String) -> some View {
        Label(title, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }

    private func inlineMessage(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

private struct DayNightThumbnail: View {
    let wallpaper: ManagedWallpaper

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: wallpaper.thumbnailExists ? "photo" : "photo.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: wallpaper.id) {
            image = await Task.detached(priority: .utility) {
                NSImage(contentsOf: wallpaper.thumbnailURL)
            }.value
        }
    }
}
