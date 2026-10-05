import AppKit
import SwiftUI

struct DayNightWallpaperSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var isExpanded: Bool

    init(isExpanded: Binding<Bool>) {
        _isExpanded = isExpanded
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Day/Night Wallpaper")
                        .font(.headline)
                    Text(model.dayNightStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(isExpanded ? "Done" : "Edit", systemImage: isExpanded ? "checkmark" : "pencil") {
                    setExpanded(!isExpanded)
                }
                .buttonStyle(.borderless)
                .disabled(model.isWorking)
                .accessibilityLabel(isExpanded ? "Done editing Day/Night choices" : "Edit Day/Night choices")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .help(isExpanded ? "Collapse Day/Night choices" : "Edit saved Day/Night choices")
            }

            if let pair = model.registeredDayNightPair {
                pairSummary(
                    label: "Current pair",
                    dayID: pair.dayAssetID,
                    nightID: pair.nightAssetID
                )
                if !draftMatches(pair) {
                    pairSummary(
                        label: "Saved choices",
                        dayID: model.dayNightDraft.dayAssetID,
                        nightID: model.dayNightDraft.nightAssetID
                    )
                }
            } else if model.dayNightDraft.dayAssetID != nil || model.dayNightDraft.nightAssetID != nil {
                pairSummary(
                    label: "Saved choices",
                    dayID: model.dayNightDraft.dayAssetID,
                    nightID: model.dayNightDraft.nightAssetID
                )
            }

            ForEach(model.dayNightMediaRecoveryMessages, id: \.self) { recoveryMessage in
                Label {
                    Text(recoveryMessage)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }

            if isExpanded {
                dayNightEditor(model: model)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
        .onAppear(perform: reconcileExpansion)
        .onChange(of: model.dayNightSectionAttentionToken) { _, _ in reconcileExpansion() }
    }

    private func dayNightEditor(model: AppModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choosing videos saves these choices. Apply registers the pair and updates every Space and display. macOS switches between them using the sun’s position, even after AerialDrop quits.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                roleEditor(
                    title: "Day",
                    selection: Binding(get: { model.dayWallpaperID }, set: { model.dayWallpaperID = $0 }),
                    selectedID: model.dayWallpaperID
                )
                roleEditor(
                    title: "Night",
                    selection: Binding(get: { model.nightWallpaperID }, set: { model.nightWallpaperID = $0 }),
                    selectedID: model.nightWallpaperID
                )
            }

            if let reason = model.dayNightUnavailableReason {
                inlineMessage(reason, systemImage: "exclamationmark.triangle")
            } else if let blocker = model.dayNightApplyBlockerMessage,
                      !model.dayNightMediaRecoveryMessages.contains(where: { $0.hasSuffix(blocker) }) {
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

    private func reconcileExpansion() {
        var preference = AppPreferences.dayNightSectionExpansionPreference()
        let previousPreference = preference
        let shouldExpand = DayNightSectionExpansionState.reconcile(
            attentionToken: model.dayNightSectionAttentionToken,
            preference: &preference
        )
        if preference != previousPreference {
            AppPreferences.setDayNightSectionExpansionPreference(preference)
        }
        if isExpanded != shouldExpand {
            isExpanded = shouldExpand
        }
    }

    private func setExpanded(_ expanded: Bool) {
        var preference = AppPreferences.dayNightSectionExpansionPreference()
        DayNightSectionExpansionState.recordUserChoice(
            expanded: expanded,
            attentionToken: model.dayNightSectionAttentionToken,
            preference: &preference
        )
        AppPreferences.setDayNightSectionExpansionPreference(preference)
        isExpanded = expanded
    }

    private func draftMatches(_ pair: DayNightWallpaperPair) -> Bool {
        model.dayNightDraft.dayAssetID == pair.dayAssetID
            && model.dayNightDraft.nightAssetID == pair.nightAssetID
    }

    private func pairSummary(label: String, dayID: String?, nightID: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                memberSummary(role: "Day", selectedID: dayID)
                memberSummary(role: "Night", selectedID: nightID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func memberSummary(role: String, selectedID: String?) -> some View {
        HStack(alignment: .center, spacing: 7) {
            if let selectedID, let wallpaper = wallpaper(for: selectedID) {
                DayNightThumbnail(wallpaper: wallpaper, size: CGSize(width: 56, height: 32))
            } else {
                Image(systemName: selectedID == nil ? "plus.rectangle.on.rectangle" : "photo.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 56, height: 32)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let selectedID, let wallpaper = wallpaper(for: selectedID) {
                    Text(wallpaper.title)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(wallpaper.title)
                } else {
                    Text(selectedID == nil ? "Choose wallpaper" : "Wallpaper missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
    let size: CGSize

    @State private var image: NSImage?

    init(wallpaper: ManagedWallpaper, size: CGSize = CGSize(width: 72, height: 40)) {
        self.wallpaper = wallpaper
        self.size = size
    }

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
        .frame(width: size.width, height: size.height)
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
