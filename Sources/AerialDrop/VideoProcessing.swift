import CoreGraphics
import Foundation

/// Media operations used by AppModel, injectable so import ownership can be tested
/// while encoding or metadata work is suspended.
protocol VideoProcessing: Sendable {
    func validate(source: URL) async throws
    func effectiveSourceDuration(for source: URL) async -> Double?
    func sourceDisplaySize(for source: URL) async throws -> CGSize
    func makeNativeMOV(
        from source: URL,
        destination: URL,
        options: ConversionOptions,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CGSize
    func generateThumbnail(from video: URL, destination: URL) async throws
}

extension VideoProcessor: VideoProcessing { }
