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
        // Assign after update: a URL change runs teardown inside update, and
        // teardown clears the stored callback for hygiene; the new item's
        // KVO reports are delivered asynchronously, after this assignment.
        nsView.update(url: url, isPlaying: isPlaying)
        nsView.onPlaybackStateChange = onPlaybackStateChange
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
    private var currentItemObservation: NSKeyValueObservation?
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
        currentItemObservation?.invalidate()
        currentItemObservation = nil
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
        onPlaybackStateChange = nil
    }

    private func load(url: URL, isPlaying: Bool) {
        teardown()
        let template = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: template)
        self.player = queuePlayer
        self.looper = looper
        currentURL = url
        playerLayer.player = queuePlayer
        observeCurrentItem(of: queuePlayer, fallback: template)
        report(.loading)
        updatePlayback(isPlaying: isPlaying)
    }

    /// AVPlayerLooper plays replicas of the template item, so the queue's
    /// currentItem — not the template — is what actually renders. Observe the
    /// player's currentItem and rebind the status observation every time the
    /// looper advances to a new replica, so a failure of the item genuinely on
    /// screen is what surfaces. Falls back to the template until the looper
    /// inserts its first replica (currentItem is nil during that window).
    ///
    /// Changes are observed where registered (the main run loop) but the hop
    /// keeps the strict-concurrency contract explicit. Identity guards keep a
    /// torn-down player's or item's late callback from overwriting the state
    /// of what replaced it (fast preview switching).
    private func observeCurrentItem(of player: AVQueuePlayer, fallback: AVPlayerItem) {
        currentItemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.player === observedPlayer else { return }
                self.bindStatusObservation(to: observedPlayer.currentItem ?? fallback)
            }
        }
    }

    private func bindStatusObservation(to item: AVPlayerItem) {
        guard item !== currentItem else { return }
        statusObservation?.invalidate()
        statusObservation = nil
        currentItem = item
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
