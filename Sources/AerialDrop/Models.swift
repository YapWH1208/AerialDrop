import Foundation

struct ManagedWallpaper: Identifiable, Hashable {
    let id: String
    let title: String
    let videoURL: URL
    let thumbnailURL: URL

    var videoExists: Bool {
        FileManager.default.fileExists(atPath: videoURL.path)
    }

    var thumbnailExists: Bool {
        FileManager.default.fileExists(atPath: thumbnailURL.path)
    }
}

enum ImportStage: Equatable {
    case idle
    case validating
    case preparingFolders
    case processingVideo
    case generatingThumbnail
    case updatingManifest
    case refreshingSystem
    case finished

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .validating: return "Validating video…"
        case .preparingFolders: return "Preparing wallpaper folders…"
        case .processingVideo: return "Building an 80-second native HEVC Aerial stream…"
        case .generatingThumbnail: return "Generating thumbnail…"
        case .updatingManifest: return "Updating the Aerial manifest…"
        case .refreshingSystem: return "Finishing catalogue installation…"
        case .finished: return "Imported"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0
        case .validating: return 0.15
        case .preparingFolders: return 0.3
        case .processingVideo: return 0.55
        case .generatingThumbnail: return 0.7
        case .updatingManifest: return 0.82
        case .refreshingSystem: return 0.95
        case .finished: return 1
        }
    }

    var icon: String {
        switch self {
        case .idle: return "square.and.arrow.down"
        case .validating: return "checkmark.seal"
        case .preparingFolders: return "folder"
        case .processingVideo: return "film"
        case .generatingThumbnail: return "photo"
        case .updatingManifest: return "rectangle.stack.badge.plus"
        case .refreshingSystem: return "arrow.triangle.2.circlepath"
        case .finished: return "checkmark.circle.fill"
        }
    }
}

enum AerialDropError: LocalizedError {
    case unsupportedOS
    case unsupportedFile
    case missingManifest(URL)
    case malformedManifest(String)
    case noVideoTrack
    case exportSessionUnavailable
    case exportFailed(String)
    case thumbnailFailed
    case invalidTitle
    case wallpaperNotFound
    case videoTooShort
    case incompatibleExportCodec
    case incompatibleSourceCodec
    case passthroughUnavailable
    case installedFileMissing(URL)
    case nativeVideoTooShort(Double)
    case nativeVideoDoesNotStartAtZero(Double)
    case nativeVideoWrongFrameRate(Float)
    case nativeVideoNotMain10(Int)
    case nativeVideoNotFullRange
    case main10EncodingUnavailable
    case manifestChangedDuringOperation
    case foreignManifestDataChanged(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "AerialDrop requires macOS Tahoe 26 or newer."
        case .unsupportedFile:
            return "Choose an MP4 or MOV video."
        case .missingManifest(let url):
            return "The Tahoe Aerial manifest was not found at:\n\(url.path)\n\nOpen System Settings → Wallpaper and download at least one Apple Aerial wallpaper first."
        case .malformedManifest(let reason):
            return "The Aerial manifest is not in the expected format: \(reason)"
        case .noVideoTrack:
            return "The selected file does not contain a readable video track."
        case .exportSessionUnavailable:
            return "macOS could not create a video export session for this file."
        case .exportFailed(let reason):
            return "Video conversion failed: \(reason)"
        case .thumbnailFailed:
            return "A thumbnail could not be generated from the video."
        case .invalidTitle:
            return "Enter a wallpaper name."
        case .wallpaperNotFound:
            return "The managed wallpaper entry was not found."
        case .videoTooShort:
            return "The selected video is too short to use as an Aerial wallpaper."
        case .incompatibleExportCodec:
            return "The exported MOV is not HEVC, so it was not installed."
        case .incompatibleSourceCodec:
            return "The source video must use H.264 or HEVC."
        case .passthroughUnavailable:
            return "macOS could not export this source as a native HEVC MOV."
        case .installedFileMissing(let url):
            return "A required installed file is missing:\n\(url.path)"
        case .nativeVideoTooShort(let seconds):
            return String(format: "The native Aerial export is only %.3f seconds long; at least 79.5 seconds are required.", seconds)
        case .nativeVideoDoesNotStartAtZero(let seconds):
            return String(format: "The native Aerial export begins at %.6f seconds instead of timestamp zero.", seconds)
        case .nativeVideoWrongFrameRate(let frameRate):
            return String(format: "The native Aerial export is %.3f fps instead of 30 fps.", frameRate)
        case .nativeVideoNotMain10(let bits):
            return "The native Aerial export is only \(bits)-bit. Tahoe custom Aerial playback requires the 10-bit HEVC Main10 media class used by the working Wallper asset."
        case .nativeVideoNotFullRange:
            return "The native Aerial export is limited-range video. The working Tahoe custom Aerial asset uses full-range 10-bit HEVC."
        case .main10EncodingUnavailable:
            return "This Mac could not initialize the HEVC Main10 encoder required for reliable Tahoe Aerial playback."
        case .manifestChangedDuringOperation:
            return "The Aerial catalogue changed while AerialDrop was working. Nothing else was overwritten. Close Wallper and System Settings, then try again."
        case .foreignManifestDataChanged(let description):
            return "AerialDrop refused to write because the change would alter \(description)."
        }
    }
}
