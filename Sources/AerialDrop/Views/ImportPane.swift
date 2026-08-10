import SwiftUI

struct ImportPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Source Video")
                        .font(.headline)

                    ImportSourceView(
                        url: model.selectedVideo,
                        resolution: model.sourceResolution,
                        cropOffset: model.cropOffset,
                        isValid: model.isSelectedVideoValid,
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
                        onSubmit: {
                            if model.canImport {
                                model.importSelectedVideo()
                            }
                        }
                    )
                }

                if model.importSucceeded {
                    ImportSuccessView(
                        onOpenSettings: { model.openWallpaperSettings() },
                        onDismiss: { model.importSucceeded = false }
                    )
                } else if model.isWorking {
                    ImportProgressView(
                        stage: model.stage,
                        progress: model.displayProgress,
                        onCancel: { model.cancelImport() }
                    )
                }

                ImportDetailsView()

                HStack {
                    Text("Automatic activation can be changed in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Import Wallpaper", systemImage: "square.and.arrow.down") {
                        model.importSelectedVideo()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canImport)
                    .help("Import the selected video (⌘↩)")
                }
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.success, trigger: model.stage, condition: { old, new in
            new == .finished && old != .finished
        })
    }
}

private struct ImportSourceView: View {
    let url: URL?
    let resolution: CGSize?
    let cropOffset: Double
    let isValid: Bool
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
            guard let first = urls.first else { return false }
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
    let onSubmit: () -> Void

    var body: some View {
        GroupBox("Wallpaper Details") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    settingLabel("Name")
                    TextField("Wallpaper name", text: $title)
                        .onSubmit(onSubmit)
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
        }
    }

    private var isUltrawideSource: Bool {
        guard let sourceResolution else { return false }
        return isUltrawide(sourceResolution)
    }

    private var cropPreset: Binding<Double> {
        Binding(
            get: { nearestCropPreset(cropOffset) },
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
                }

                ProgressView(value: progress)

                HStack {
                    Text("AerialDrop keeps the source video unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Cancel", role: .cancel, action: onCancel)
                        .controlSize(.small)
                }
            }
            .padding(4)
        }
    }
}

private struct ImportSuccessView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Imported successfully")
                        .font(.headline)
                    Text("The wallpaper has been added to the native Aerial catalogue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Wallpaper Settings", systemImage: "gearshape", action: onOpenSettings)

                Button("Dismiss", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .help("Dismiss")
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ImportDetailsView: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("How AerialDrop installs this wallpaper", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Builds an 80-second, 30 fps HEVC Main10 stream", systemImage: "film")
                Label("Creates a Tahoe-compatible HEIF preview", systemImage: "photo")
                Label("Backs up entries.json and preserves foreign entries", systemImage: "doc.badge.gearshape")
                Label("Adds the result to the native Aerial catalogue", systemImage: "rectangle.stack")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
        .font(.callout)
    }
}
