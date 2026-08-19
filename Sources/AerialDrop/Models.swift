import Foundation

enum LibrarySortOrder: String, CaseIterable {
    case title
    case recentlyAdded
}

extension [ManagedWallpaper] {
    /// The Library's ordering: title (localized, the manifest's natural order)
    /// or Recently Added (import order descending, titles breaking ties).
    func sortedForLibrary(_ order: LibrarySortOrder) -> [ManagedWallpaper] {
        switch order {
        case .title:
            return self
        case .recentlyAdded:
            return sorted { lhs, rhs in
                let lhsOrder = lhs.preferredOrder ?? Int.min
                let rhsOrder = rhs.preferredOrder ?? Int.min
                if lhsOrder != rhsOrder {
                    return lhsOrder > rhsOrder
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

/// A user-facing alert with a workflow- and outcome-scoped title, so the
/// user can tell what happened (and whether it was a failure) at a glance
/// instead of reading a body under a generic app-name heading.
struct AppAlert: Equatable {
    let title: String
    let message: String
}

struct ManagedWallpaper: Identifiable, Hashable {
    let id: String
    let title: String
    let videoURL: URL
    let thumbnailURL: URL
    var resolution: CGSize? = nil
    /// Import order from the manifest (higher = added more recently), used
    /// for the Library's "Recently Added" sort. Nil for entries without it.
    var preferredOrder: Int? = nil

    var videoExists: Bool {
        FileManager.default.fileExists(atPath: videoURL.path)
    }

    var thumbnailExists: Bool {
        FileManager.default.fileExists(atPath: thumbnailURL.path)
    }
}

enum CatalogueState: Equatable {
    case loading
    case ready
    case unavailable(String)
}

/// Result of reading macOS's private wallpaper-selection store immediately
/// before a destructive action is presented or executed.
enum RemovalReadiness: Equatable {
    case verifiedInactive
    case verifiedActive
    case unknown
}

enum ImportActivationResult: Equatable {
    case activatedEverywhere
    case installedOnly
    case activationFailed
}

struct ImportOutcome: Equatable {
    let wallpaper: ManagedWallpaper
    let activationResult: ImportActivationResult
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

    var allowsCancellation: Bool {
        switch self {
        case .validating, .preparingFolders, .processingVideo, .generatingThumbnail:
            return true
        case .idle, .updatingManifest, .refreshingSystem, .finished:
            return false
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
    case insufficientImportStorage(requiredBytes: Int64, availableBytes: Int64)
    case manifestChangedDuringOperation
    case foreignManifestDataChanged(String)
    case missingWallpaperSelectionStore(URL)
    case malformedWallpaperSelectionStore(String)
    case wallpaperSelectionStoreChangedDuringOperation
    case foreignWallpaperSelectionDataChanged(String)
    case wallpaperSelectionVerificationFailed(String)
    case activeWallpaperCannotBeRemoved
    case wallpaperSelectionUnknownForRemoval
    case backupRestoreRejected(String)

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
            let hint = reason.contains("OSStatus")
                ? " Try freeing up disk space and using a lower quality or resolution."
                : ""
            return "Video conversion failed: \(reason)\(hint)"
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
            return "The source video must use H.264 or HEVC. Convert or re-export the video in that format, then import it again."
        case .passthroughUnavailable:
            return "macOS could not export this source as a native HEVC MOV."
        case .installedFileMissing(let url):
            return "A required installed file is missing:\n\(url.path)"
        case .nativeVideoTooShort(let seconds):
            return "The native Aerial export is only \(seconds.formatted(.number.precision(.fractionLength(3)))) seconds long; at least 79.5 seconds are required."
        case .nativeVideoDoesNotStartAtZero(let seconds):
            return "The native Aerial export begins at \(seconds.formatted(.number.precision(.fractionLength(6)))) seconds instead of timestamp zero."
        case .nativeVideoWrongFrameRate(let frameRate):
            return "The native Aerial export is \(frameRate.formatted(.number.precision(.fractionLength(3)))) fps instead of 30 fps."
        case .nativeVideoNotMain10(let bits):
            return "The native Aerial export is only \(bits)-bit. Tahoe custom Aerial playback requires the 10-bit HEVC Main10 media format."
        case .nativeVideoNotFullRange:
            return "The native Aerial export is limited-range video. Tahoe custom Aerial playback requires full-range 10-bit HEVC."
        case .main10EncodingUnavailable:
            return "This Mac could not initialize the HEVC Main10 encoder required for reliable Tahoe Aerial playback."
        case .insufficientImportStorage(let requiredBytes, let availableBytes):
            let required = ByteCountFormatter.string(
                fromByteCount: requiredBytes,
                countStyle: .file
            )
            let available = ByteCountFormatter.string(
                fromByteCount: availableBytes,
                countStyle: .file
            )
            return "Import needs about \(required) of free space while AerialDrop builds the wallpaper, but only \(available) is available. Free up space or choose a lower quality or resolution, then try again."
        case .manifestChangedDuringOperation:
            return "The Aerial catalogue changed while AerialDrop was working. Nothing else was overwritten. Close System Settings and any other wallpaper app, then try again."
        case .foreignManifestDataChanged(let description):
            return "AerialDrop refused to write because the change would alter \(description)."
        case .missingWallpaperSelectionStore(let url):
            return "The Tahoe wallpaper selection store was not found at:\n\(url.path)\n\nOpen System Settings → Wallpaper once, then try again."
        case .malformedWallpaperSelectionStore(let reason):
            return "The Tahoe wallpaper selection store is not in the expected format: \(reason)"
        case .wallpaperSelectionStoreChangedDuringOperation:
            return "The wallpaper selection changed while AerialDrop was working. Nothing else was overwritten. Close System Settings and try again."
        case .foreignWallpaperSelectionDataChanged(let description):
            return "AerialDrop refused to write because the change would alter \(description)."
        case .wallpaperSelectionVerificationFailed(let expectedID):
            return "AerialDrop wrote the wallpaper selection, but macOS did not confirm the expected Aerial (\(expectedID)). Your backup was kept and no automatic restore was attempted."
        case .activeWallpaperCannotBeRemoved:
            return "Choose another wallpaper before removing the AerialDrop wallpaper that is currently active."
        case .wallpaperSelectionUnknownForRemoval:
            return "AerialDrop couldn’t verify which wallpaper is active. Check again, open Wallpaper Settings, or explicitly choose Remove Anyway before continuing."
        case .backupRestoreRejected(let reason):
            return "The backup could not be restored. \(reason) Nothing was changed."
        }
    }
}
