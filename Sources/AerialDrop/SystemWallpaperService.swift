import AppKit
import Foundation

struct SystemWallpaperService {
    /// Reloads the Aerial catalogue after a manifest update.
    func refresh() async {
        await terminateProcess(named: "WallpaperAerialsExtension", signal: nil)
        await terminateProcess(named: "WallpaperAgent", signal: nil)
        try? await Task.sleep(for: .seconds(1))
    }

    private func terminateProcess(named name: String, signal: String?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            if let signal {
                process.arguments = [signal, name]
            } else {
                process.arguments = [name]
            }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in continuation.resume() }

            do {
                try process.run()
            } catch {
                continuation.resume()
            }
        }
    }

    @MainActor
    func openWallpaperSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @MainActor
    func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @MainActor
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
