import AppKit
import SwiftUI

struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title2.weight(.semibold))
            .tracking(AerialTheme.displayTracking)
            .foregroundStyle(.primary)
    }
}

struct ImportPane: View {
    @Environment(AppModel.self) private var model
    @State private var hoveringDropZone = false

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "Import a Video", systemImage: "square.and.arrow.down")

                dropZone

                if isWide {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Crop")
                            .font(.callout.weight(.semibold))
                        Picker("Position", selection: cropPreset) {
                            Text("Left").tag(0.0)
                            Text("Center").tag(0.5)
                            Text("Right").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        Slider(value: $model.cropOffset, in: 0...1)
                            .help("Position of the visible 16:9 window")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Conversion")
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 16) {
                        Picker("Quality", selection: $model.conversionQuality) {
                            Text("Standard").tag(ConversionOptions.Quality.standard)
                            Text("High").tag(ConversionOptions.Quality.high)
                            Text("Maximum").tag(ConversionOptions.Quality.maximum)
                        }
                        Picker("Output resolution", selection: $model.outputHeightCap) {
                            Text("Original").tag(Int?.none)
                            ForEach(availableHeightCaps, id: \.self) { cap in
                                Text("\(cap)p").tag(Int?.some(cap))
                            }
                        }
                        Spacer()
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallpaper name")
                        .font(.callout.weight(.medium))
                    TextField("Example: Yoimiya 4K", text: $model.title)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .onSubmit {
                            if model.canImport { model.importSelectedVideo() }
                        }
                }

                if model.importSucceeded {
                    successCard
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                } else if model.isWorking {
                    progressCard
                        .transition(.scale(scale: 0.97).combined(with: .opacity))
                }

                Button {
                    model.importSelectedVideo()
                } label: {
                    Label {
                        Text("Import into Aerials")
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                            .symbolEffect(.pulse, options: .repeating, isActive: model.isWorking)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canImport)
                .help("Import the selected video (⌘↩)")

                whatHappensCard

                Spacer(minLength: 8)

                Text("After importing, select the new item in System Settings → Wallpaper; macOS applies it to Desktop, Lock Screen and Screen Saver natively. You may quit AerialDrop after setup; macOS handles playback natively.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.success, trigger: model.stage, condition: { old, new in
            new == .finished && old != .finished
        })
    }

    private var dropZone: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: 360, height: 360)
                .blur(radius: 80)
                .allowsHitTesting(false)
            dropZoneButton
        }
        .frame(maxWidth: .infinity)
    }

    private var isWide: Bool {
        guard let resolution = model.sourceResolution else { return false }
        return isWiderThan16By9(resolution)
    }

    /// Segmented-preset binding: snaps the continuous slider position to the
    /// nearest preset; picking a preset sets the slider value.
    private var cropPreset: Binding<Double> {
        Binding(
            get: { nearestCropPreset(model.cropOffset) },
            set: { model.cropOffset = $0 }
        )
    }

    /// Downscale-only resolution options, derived from the source height.
    private var availableHeightCaps: [Int] {
        guard let sourceHeight = model.sourceResolution?.height else { return [] }
        return [2160, 1440, 1080].filter { $0 < Int(sourceHeight) }
    }

    private var dropZoneButton: some View {
        Button {
            model.showingFileImporter = true
        } label: {
            VStack(spacing: 12) {
                if let url = model.selectedVideo {
                    VideoPreview(
                        url: url,
                        resolution: model.sourceResolution,
                        cropOffset: isWide ? model.cropOffset : nil
                    )
                    .frame(maxWidth: 640, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topTrailing) {
                            Label("Click to change", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .padding(10)
                        }
                    Text(url.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 30, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .padding(18)
                        .glassEffect(.regular, in: Circle())
                        .symbolEffect(.bounce, value: hoveringDropZone)
                    Text("Choose or drop a video")
                        .font(.headline)
                    Text("MP4 or MOV · The source file is not modified")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 260)
            .padding(16)
            .glassEffect(.regular.tint(.accentColor.opacity(0.22)), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    .foregroundStyle(hoveringDropZone ? AnyShapeStyle(.tint.opacity(0.6)) : AnyShapeStyle(.quaternary))
            }
            .scaleEffect(hoveringDropZone ? 1.012 : 1)
        }
        .buttonStyle(PressScaleButtonStyle())
        .onHover { hovering in
            hoveringDropZone = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.25), value: hoveringDropZone)
        .dropDestination(for: URL.self) { urls, _ in
            guard let first = urls.first else { return false }
            model.chooseVideo(first)
            return true
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: model.stage.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating, isActive: model.stage != .finished)
                    .foregroundStyle(.tint)
                Text(model.stage.label)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(Int(model.displayProgress * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            ProgressView(value: model.displayProgress)
                .tint(.accentColor)
            HStack {
                Spacer()
                Button("Cancel Import", role: .cancel) {
                    model.cancelImport()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Stop the import and keep the current selection")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private var successCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AerialTheme.success)
                Text("Imported successfully")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    model.importSucceeded = false
                } label: {
                    Label("Dismiss", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
                .help("Dismiss")
            }
            Text("Select the new item under AerialDrop in System Settings → Wallpaper; macOS applies it to Desktop, Lock Screen and Screen Saver natively.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(AerialTheme.success.opacity(0.15)), in: .rect(cornerRadius: 18))
    }

    private var whatHappensCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What happens")
                .font(.callout.weight(.semibold))
            ForEach(whatHappensRows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 26, height: 26)
                        .background(.tint.opacity(0.14), in: Circle())
                    Text(row.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private struct WhatHappensRow: Identifiable {
        let id = UUID()
        let icon: String
        let text: String
    }

    private let whatHappensRows: [WhatHappensRow] = [
        WhatHappensRow(icon: "film", text: "Builds an 80-second, 30 fps HEVC Main10 stream with native temporal sub-layers"),
        WhatHappensRow(icon: "photo", text: "Normalizes timestamp zero and creates a Tahoe-compatible HEIF preview"),
        WhatHappensRow(icon: "doc.badge.gearshape", text: "Backs up entries.json and preserves other apps’ entries"),
        WhatHappensRow(icon: "rectangle.stack", text: "Adds a complete Tahoe Aerial catalogue entry")
    ]
}