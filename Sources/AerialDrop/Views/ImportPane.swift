import SwiftUI

struct ImportPane: View {
    let onViewLibrary: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage(AppPreferences.setWallpaperAfterImportKey) private var setWallpaperAfterImport = true
    @AccessibilityFocusState private var accessibilityStatus: ImportAccessibilityStatus?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.importOutcome != nil {
                importWorkflow(model: model)
            } else {
                switch model.catalogueState {
                case .ready:
                    importWorkflow(model: model)
                case .loading, .unavailable:
                    CatalogueAccessView(
                        state: model.catalogueState,
                        onOpenSettings: model.openWallpaperSettings,
                        onCheckAgain: { Task { await model.reload() } }
                    )
                }
            }
        }
        .sensoryFeedback(trigger: model.stage) { old, new in
            guard new == .finished, old != .finished else { return nil }
            return importFinishedWithFailure ? .error : .success
        }
        .onChange(of: model.stage) { oldStage, newStage in
            guard oldStage != newStage,
                  model.isWorking,
                  newStage != .finished else { return }
            AccessibilityNotification.Announcement(newStage.label).post()
        }
        .onChange(of: model.importOutcome) { _, outcome in
            guard outcome != nil else { return }
            accessibilityStatus = .completion
        }
    }

    private func importWorkflow(model: AppModel) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let outcome = model.importOutcome {
                    ImportSuccessView(
                        outcome: outcome,
                        onViewLibrary: onViewLibrary,
                        onImportAnother: beginAnotherImport,
                        onOpenWallpaperSettings: model.openWallpaperSettings
                    )
                    .accessibilityFocused($accessibilityStatus, equals: .completion)
                } else {
                    if model.isWorking {
                        ImportProgressView(
                            stage: model.stage,
                            progress: model.displayProgress,
                            eta: model.encodeETA,
                            canCancel: model.isImportCancellable,
                            onCancel: { model.cancelImport() }
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Source Video")
                            .font(.headline)

                        ImportSourceView(
                            url: model.selectedVideo,
                            resolution: model.sourceResolution,
                            cropOffset: model.cropOffset,
                            isValid: model.isSelectedVideoValid,
                            isDisabled: model.isWorking,
                            onChoose: { model.showingFileImporter = true },
                            onDrop: { model.chooseVideo($0) }
                        )
                    }

                    if model.isSelectedVideoValid {
                        ImportSettingsView(
                            title: $model.title,
                            quality: $model.conversionQuality,
                            outputHeightCap: $model.outputHeightCap,
                            cropOffset: $model.cropOffset,
                            sourceResolution: model.sourceResolution,
                            outputSummary: encodedOutputSummary,
                            duplicateTitle: duplicateTitle
                        )
                        .disabled(model.isWorking)

                        ImportActivationView(isEnabled: $setWallpaperAfterImport)
                            .disabled(model.isWorking)
                    }

                    ImportDetailsView()
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }

    private var importFinishedWithFailure: Bool {
        model.importOutcome?.activationResult == .activationFailed
    }

    /// The encoded frame size and an estimated output size for the 80-second
    /// loop, derived from the same pure functions the pipeline uses, so the
    /// user sees the consequences of the quality/resolution choices in advance.
    /// The trimmed wallpaper name when an existing wallpaper already uses it.
    private var duplicateTitle: String? {
        let clean = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        guard model.wallpapers.contains(where: {
            $0.title.localizedCaseInsensitiveCompare(clean) == .orderedSame
        }) else { return nil }
        return clean
    }

    private var encodedOutputSummary: String? {
        guard let source = model.sourceResolution else { return nil }
        let size = encodedOutputSize(sourceSize: source, outputHeightCap: model.outputHeightCap)
        let bitrate = bitrateBps(quality: model.conversionQuality, renderHeight: Int(size.height))
        let megabytes = Int(Double(bitrate) * 80.0 / 8.0 / 1_000_000)
        return "\(Int(size.width)) × \(Int(size.height)) · est. \(megabytes) MB"
    }

    private func beginAnotherImport() {
        model.importOutcome = nil
        model.showingFileImporter = true
    }
}

private enum ImportAccessibilityStatus: Hashable {
    case completion
}

private struct ImportActivationView: View {
    @Binding var isEnabled: Bool

    var body: some View {
        GroupBox("After Import") {
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Set as wallpaper after importing", isOn: $isEnabled)

                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var description: String {
        if isEnabled {
            "The new wallpaper will be applied across all Spaces and displays."
        } else {
            "The video will be installed without changing your current wallpaper."
        }
    }
}

private struct ImportSourceView: View {
    let url: URL?
    let resolution: CGSize?
    let cropOffset: Double
    let isValid: Bool
    let isDisabled: Bool
    let onChoose: () -> Void
    let onDrop: (URL) -> Void

    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        Group {
            if let url {
                selectedSource(url)
            } else {
                emptySource
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !isDisabled, let first = urls.first else { return false }
            onDrop(first)
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
    }

    private var emptySource: some View {
        Button(action: onChoose) {
            VStack(spacing: 10) {
                Image(systemName: "film.stack")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)

                Text("Choose or drop a video")
                    .font(.headline)

                Text("MP4 or MOV · Your source file is never modified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dropTargeted || hovering ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    dropTargeted || hovering ? Color.accentColor : Color(nsColor: .separatorColor),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6])
                )
        }
        .onHover { hovering = $0 }
        .accessibilityHint("Opens a file chooser for an MP4 or MOV video")
    }

    private func selectedSource(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VideoPreview(
                url: url,
                resolution: resolution,
                cropOffset: cropOffset
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if isValid {
                        Label("Ready to configure", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Validating video…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Replace…", systemImage: "arrow.triangle.2.circlepath", action: onChoose)
                    .disabled(isDisabled)
            }
        }
    }
}

private struct ImportSettingsView: View {
    @Binding var title: String
    @Binding var quality: ConversionOptions.Quality
    @Binding var outputHeightCap: Int?
    @Binding var cropOffset: Double

    let sourceResolution: CGSize?
    let outputSummary: String?
    let duplicateTitle: String?

    @FocusState private var nameIsFocused: Bool

    var body: some View {
        GroupBox("Wallpaper Details") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    settingLabel("Name")
                    TextField("Enter a wallpaper name", text: $title)
                        .focused($nameIsFocused)
                        .onSubmit { nameIsFocused = false }
                }

                GridRow {
                    settingLabel("Quality")
                    Picker("Quality", selection: $quality) {
                        Text("Standard").tag(ConversionOptions.Quality.standard)
                        Text("High").tag(ConversionOptions.Quality.high)
                        Text("Maximum").tag(ConversionOptions.Quality.maximum)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                GridRow {
                    settingLabel("Resolution")
                    Picker("Output resolution", selection: $outputHeightCap) {
                        Text("Original").tag(Int?.none)
                        ForEach(availableHeightCaps, id: \.self) { cap in
                            Text("\(cap)p").tag(Int?.some(cap))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240, alignment: .leading)
                }

                if let outputSummary {
                    GridRow {
                        settingLabel("Output")
                        Text(outputSummary)
                    }
                }

                if isUltrawideSource {
                    GridRow(alignment: .top) {
                        settingLabel("Crop")
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Crop position", selection: cropPreset) {
                                Text("Left").tag(0.0)
                                Text("Center").tag(0.5)
                                Text("Right").tag(1.0)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            Slider(value: $cropOffset, in: 0...1)
                                .accessibilityLabel("Crop position")
                                .help("Position of the visible 16:9 window")
                        }
                    }
                }
            }
            .padding(8)

            if let duplicateTitle {
                Label(
                    "A wallpaper named “\(duplicateTitle)” already exists. Importing will create a duplicate.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private var isUltrawideSource: Bool {
        guard let sourceResolution else { return false }
        return isUltrawide(sourceResolution)
    }

    private var cropPreset: Binding<Double> {
        Binding(
            get: {
                let nearest = nearestCropPreset(cropOffset)
                if abs(cropOffset - nearest) <= 0.05 { return nearest }
                return -1 // between presets: no segment highlighted
            },
            set: { cropOffset = $0 }
        )
    }

    private var availableHeightCaps: [Int] {
        guard let sourceResolution else { return [] }
        return [2160, 1440, 1080].filter {
            CGFloat($0) < naturalWindowHeight(sourceSize: sourceResolution)
        }
    }

    private func settingLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 82, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }
}

private struct ImportProgressView: View {
    let stage: ImportStage
    let progress: Double
    let eta: TimeInterval?
    let canCancel: Bool
    let onCancel: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Label(stage.label, systemImage: stage.icon)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let etaText {
                        Text(etaText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                ProgressView(value: progress)

                HStack {
                    Text(canCancel ? cancellableMessage : finishingMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if canCancel {
                        Button("Cancel", role: .cancel, action: onCancel)
                            .controlSize(.small)
                    }
                }
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import progress")
    }

    private var etaText: String? {
        guard let eta, eta > 5 else { return nil }
        if eta >= 60 {
            return "≈ \(Int(eta / 60)) min left"
        }
        return "≈ \(Int(eta)) s left"
    }

    private var cancellableMessage: String {
        "The source video stays unchanged. You can cancel before installation begins."
    }

    private var finishingMessage: String {
        "Finishing installation. This step can’t be cancelled."
    }
}

private struct ImportSuccessView: View {
    let outcome: ImportOutcome
    let onViewLibrary: () -> Void
    let onImportAnother: () -> Void
    let onOpenWallpaperSettings: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: outcome.activationResult == .activationFailed
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(outcome.activationResult == .activationFailed ? Color.orange : Color.green)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(outcome.completionTitle)
                            .font(.headline)
                        Text(outcome.completionMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()

                    Button("Open Wallpaper Settings", systemImage: "photo", action: onOpenWallpaperSettings)
                    Button("Import Another", systemImage: "plus", action: onImportAnother)
                    Button("View in Library", systemImage: "photo.on.rectangle.angled", action: onViewLibrary)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(outcome.accessibilityAnnouncement)
    }
}

private extension ImportOutcome {
    var completionTitle: String {
        switch activationResult {
        case .activatedEverywhere:
            "Imported and Set as Wallpaper"
        case .installedOnly:
            "Imported Without Changing Wallpaper"
        case .activationFailed:
            "Imported; Activation Needs Attention"
        }
    }

    var completionMessage: String {
        switch activationResult {
        case .activatedEverywhere:
            "“\(wallpaper.title)” is active across all Spaces and displays."
        case .installedOnly:
            "“\(wallpaper.title)” was added to the native Aerial catalogue. Your current wallpaper was not changed."
        case .activationFailed:
            "“\(wallpaper.title)” was installed, but could not be applied. You can retry from the recovery alert or Library."
        }
    }

    var accessibilityAnnouncement: String {
        "\(completionTitle). \(completionMessage)"
    }
}

private struct ImportDetailsView: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("How AerialDrop installs this wallpaper", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Builds an 80-second, 30 fps HEVC Main10 stream", systemImage: "film")
                Label("Creates a Tahoe-compatible HEIF preview", systemImage: "photo")
                Label("Creates a backup before every catalogue change", systemImage: "doc.badge.gearshape")
                Label("Adds the result to the native Aerial catalogue", systemImage: "rectangle.stack")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .font(.callout)
    }
}
