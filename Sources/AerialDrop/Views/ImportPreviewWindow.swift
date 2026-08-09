import AVFoundation
import AVKit
import SwiftUI

struct ImportPreviewWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let url = model.selectedVideo, let sourceSize = model.sourceResolution {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack {
                        LoopingPlayerView(url: url)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        if hasCropWindow(sourceSize) {
                            CropMask(cropOffset: model.cropOffset, resolution: sourceSize)
                        }
                    }
                    .background(.black, in: RoundedRectangle(cornerRadius: 14))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    previewMetadata(sourceSize: sourceSize)
                    previewControls(model: $model)
                }
                .padding(24)
            } else {
                ContentUnavailableView("Choose a video first", systemImage: "film.stack", description: Text("Select an MP4 or MOV in the Import pane, then open Preview & Adjust."))
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private func previewMetadata(sourceSize: CGSize) -> some View {
        let output = encodedOutputSize(sourceSize: sourceSize, outputHeightCap: model.outputHeightCap)
        let bitrate = bitrateBps(quality: model.conversionQuality, renderHeight: Int(output.height))
        return HStack(spacing: 14) {
            Label("\(Int(sourceSize.width))×\(Int(sourceSize.height))", systemImage: "video")
            Label("\(Int(output.width))×\(Int(output.height))", systemImage: "rectangle.inset.filled")
            Label(bitrate.formatted(.byteCount(style: .file)) + "/s", systemImage: "speedometer")
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func previewControls(model: Bindable<AppModel>) -> some View {
        if let resolution = self.model.sourceResolution, isUltrawide(resolution) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Crop position").font(.callout.weight(.semibold))
                Picker("Crop position", selection: Binding(get: { nearestCropPreset(self.model.cropOffset) }, set: { self.model.cropOffset = $0 })) {
                    Text("Left").tag(0.0)
                    Text("Center").tag(0.5)
                    Text("Right").tag(1.0)
                }
                .pickerStyle(.segmented)
                Slider(value: model.cropOffset, in: 0...1)
                    .accessibilityLabel("Crop position")
            }
        }
        HStack {
            Picker("Quality", selection: model.conversionQuality) {
                Text("Standard").tag(ConversionOptions.Quality.standard)
                Text("High").tag(ConversionOptions.Quality.high)
                Text("Maximum").tag(ConversionOptions.Quality.maximum)
            }
            Picker("Output resolution", selection: model.outputHeightCap) {
                Text("Original").tag(Int?.none)
                ForEach(availableHeightCaps, id: \.self) { cap in
                    Text("\(cap)p").tag(Int?.some(cap))
                }
            }
        }
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
        guard scopedURL != url else { return }
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
    }

    private func load(url: URL) {
        teardown()
        if url.startAccessingSecurityScopedResource() { scopedURL = url }
        let player = AVQueuePlayer()
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: AVURLAsset(url: url)))
        self.player = player
        self.looper = looper
        playerView.player = player
        player.play()
    }
}
