import AVFoundation
import SwiftUI

/// Playback readiness of the looping preview player.
enum LoopPlaybackState {
    case loading
    case ready
    case failed
}

/// A looping AVPlayerLayer-backed player for a local video URL.
struct LoopPlayerView: NSViewRepresentable {
    let url: URL
    let isPlaying: Bool
    var onPlaybackStateChange: ((LoopPlaybackState) -> Void)? = nil

    func makeNSView(context: Context) -> PlayerNSView {
        PlayerNSView(url: url, isPlaying: isPlaying)
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.onPlaybackStateChange = onPlaybackStateChange
        nsView.update(url: url, isPlaying: isPlaying)
    }

    static func dismantleNSView(_ nsView: PlayerNSView, coordinator: Void) {
        nsView.teardown()
    }
}

final class PlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private var currentItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var lastReportedState: LoopPlaybackState?

    /// Delivered on the main thread; the representable forwards it to state.
    var onPlaybackStateChange: ((LoopPlaybackState) -> Void)?

    init(url: URL, isPlaying: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        load(url: url, isPlaying: isPlaying)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func update(url: URL, isPlaying: Bool) {
        if currentURL != url {
            load(url: url, isPlaying: isPlaying)
        } else {
            updatePlayback(isPlaying: isPlaying)
        }
    }

    func teardown() {
        statusObservation?.invalidate()
        statusObservation = nil
        looper?.disableLooping()
        player?.pause()
        looper = nil
        player = nil
        playerLayer.player = nil
        currentURL = nil
        currentItem = nil
        lastReportedState = nil
    }

    private func load(url: URL, isPlaying: Bool) {
        teardown()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        self.player = queuePlayer
        self.looper = looper
        currentURL = url
        currentItem = item
        playerLayer.player = queuePlayer
        observeItemStatus(of: item)
        report(.loading)
        updatePlayback(isPlaying: isPlaying)
    }

    /// Status changes are observed where registered (the main run loop) but
    /// the hop keeps the strict-concurrency contract explicit. The observed
    /// item is captured so a torn-down item's late callback cannot overwrite
    /// the state of the item that replaced it (fast preview switching).
    private func observeItemStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            let state: LoopPlaybackState
            switch observed.status {
            case .readyToPlay:
                state = .ready
            case .failed:
                state = .failed
            default:
                state = .loading
            }
            guard let self else { return }
            Task { @MainActor in
                guard self.currentItem === item else { return }
                self.report(state)
            }
        }
    }

    private func report(_ state: LoopPlaybackState) {
        guard state != lastReportedState else { return }
        lastReportedState = state
        onPlaybackStateChange?(state)
    }

    private func updatePlayback(isPlaying: Bool) {
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }
}
