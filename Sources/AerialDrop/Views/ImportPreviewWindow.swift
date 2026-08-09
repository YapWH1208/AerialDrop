import AVFoundation
import AVKit
import SwiftUI

struct ImportPreviewWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let url = model.selectedVideo {
                if let sourceSize = model.sourceResolution {
                    VStack(alignment: .leading, spacing: 16) {
                        ZStack {
                            LoopingPlayerView(url: url)
                                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            if hasCropWindow(sourceSize) {
                                CropMask(cropOffset: model.cropOffset, resolution: sourceSize)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.separator, lineWidth: 0.5)
                        }
                        .layoutPriority(1)
                        .accessibilityLabel("Looping source video preview")

                        previewMetadata(sourceSize: sourceSize)

                        GroupBox("Preview Settings") {
                            previewControls(model: $model)
                                .padding(6)
                        }
                    }
                    .padding(20)
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "film.stack",
                        description: Text("This video's metadata couldn't be read, so the preview and crop controls are hidden. Import still works.")
                    )
                }
            } else {
                ContentUnavailableView("Choose a video first", systemImage: "film.stack", description: Text("Select an MP4 or MOV in the Import pane, then open Preview & Adjust."))
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private func previewMetadata(sourceSize: CGSize) -> some View {
        let output = encodedOutputSize(sourceSize: sourceSize, outputHeightCap: model.outputHeightCap)
        let bitrate = bitrateBps(quality: model.conversionQuality, renderHeight: Int(output.height))
        return HStack(spacing: 16) {
            Label("\(Int(sourceSize.width))×\(Int(sourceSize.height))", systemImage: "video")
            Label("\(Int(output.width))×\(Int(output.height))", systemImage: "rectangle.inset.filled")
            Label(bitrate.formatted(.byteCount(style: .file)) + "/s", systemImage: "speedometer")
            Spacer()
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func previewControls(model: Bindable<AppModel>) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                settingLabel("Quality")
                Picker("Quality", selection: model.conversionQuality) {
                    Text("Standard").tag(ConversionOptions.Quality.standard)
                    Text("High").tag(ConversionOptions.Quality.high)
                    Text("Maximum").tag(ConversionOptions.Quality.maximum)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            GridRow {
                settingLabel("Resolution")
                Picker("Output resolution", selection: model.outputHeightCap) {
                    Text("Original").tag(Int?.none)
                    ForEach(availableHeightCaps, id: \.self) { cap in
                        Text("\(cap)p").tag(Int?.some(cap))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240, alignment: .leading)
            }

            if let resolution = self.model.sourceResolution, isUltrawide(resolution) {
                GridRow(alignment: .top) {
                    settingLabel("Crop")
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(
                            "Crop position",
                            selection: Binding(
                                get: { nearestCropPreset(self.model.cropOffset) },
                                set: { self.model.cropOffset = $0 }
                            )
                        ) {
                            Text("Left").tag(0.0)
                            Text("Center").tag(0.5)
                            Text("Right").tag(1.0)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Slider(value: model.cropOffset, in: 0...1)
                            .accessibilityLabel("Crop position")
                    }
                }
            }
        }
    }

    private func settingLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 82, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }

    private var availableHeightCaps: [Int] {
        guard let source = model.sourceResolution else { return [] }
        return [2160, 1440, 1080].filter { CGFloat($0) < naturalWindowHeight(sourceSize: source) }
    }
}

struct LoopingPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        LoopingPlayerNSView(url: url)
    }

    func updateNSView(_ view: LoopingPlayerNSView, context: Context) {
        view.update(url: url)
    }

    static func dismantleNSView(_ view: LoopingPlayerNSView, coordinator: Void) {
        view.teardown()
    }
}

@MainActor
final class LoopingPlayerNSView: NSView {
    private let playerView = AVPlayerView()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?
    private var scopedURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        playerView.controlsStyle = .floating
        playerView.videoGravity = .resizeAspect
        addSubview(playerView)
        load(url: url)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerView.frame = bounds
    }

    func update(url: URL) {
        guard loadedURL != url else { return }
        load(url: url)
    }

    func teardown() {
        looper?.disableLooping()
        player?.pause()
        looper = nil
        player = nil
        playerView.player = nil
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = nil
        loadedURL = nil
    }

    private func load(url: URL) {
        teardown()
        loadedURL = url
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: AVURLAsset(url: url)))
        self.player = player
        self.looper = looper
        playerView.player = player
        player.isMuted = true
        player.play()
    }
}
