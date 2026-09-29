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

    /// Places the oriented source in output coordinates, then fills and pans
    /// the render area. `pan` is measured in output pixels.
    static func renderTransform(
        preferredTransform: CGAffineTransform,
        transformedRect: CGRect,
        renderSize: CGSize,
        pan: CGFloat
    ) -> CGAffineTransform {
        let sourceSize = CGSize(
            width: max(2, abs(transformedRect.width)),
            height: max(2, abs(transformedRect.height))
        )
        let scale = max(
            renderSize.width / sourceSize.width,
            renderSize.height / sourceSize.height
        )
        let offsetX = (renderSize.width - sourceSize.width * scale) / 2 - pan
        let offsetY = (renderSize.height - sourceSize.height * scale) / 2

        // Concatenation applies each following operation in the oriented/output
        // coordinate system. The convenience translatedBy/scaledBy methods
        // prepend source-space operations, which displace rotated or scaled video.
        return preferredTransform
            .concatenating(CGAffineTransform(
                translationX: -transformedRect.minX, y: -transformedRect.minY
            ))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
    }
}
