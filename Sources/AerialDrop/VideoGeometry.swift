import CoreGraphics
import Foundation

/// Shared video-geometry helpers used by both the encode pipeline and the UI.
enum VideoGeometry {
    /// The display size of a video track after applying its preferred
    /// transform — the size the encode pipeline actually renders.
    ///
    /// `naturalSize` is the storage size; the `preferredTransform` rotates or
    /// mirrors it (e.g. portrait phone recordings), so the UI (crop bands,
    /// height caps, resolution badge) must apply the same transform as
    /// `VideoProcessor` or it will disagree with the encoded output.
    static func displaySize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}
