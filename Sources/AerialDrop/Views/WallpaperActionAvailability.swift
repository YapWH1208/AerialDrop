struct WallpaperActionAvailability {
    let wallpaper: ManagedWallpaper
    let isActive: Bool
    let isSelectionStatusUnknown: Bool
    let isWorking: Bool

    var canSetAsWallpaper: Bool {
        wallpaper.videoExists && !isActive && !isWorking
    }

    var canRename: Bool {
        !isWorking
    }

    var canRemove: Bool {
        (!isActive || isSelectionStatusUnknown) && !isWorking
    }

    var setWallpaperHelp: String {
        if !wallpaper.videoExists {
            return "The installed video is missing"
        }
        if isActive {
            return "This wallpaper is already active"
        }
        if isWorking {
            return "Wait for the current operation to finish"
        }
        return "Apply this wallpaper across all Spaces and displays"
    }

    var renameHelp: String {
        isWorking ? "Wait for the current operation to finish" : "Rename this wallpaper"
    }

    var removeHelp: String {
        if isSelectionStatusUnknown {
            return "Check the active wallpaper before removal"
        }
        if isActive {
            return "Choose a different wallpaper before removing this one"
        }
        if isWorking {
            return "Wait for the current operation to finish"
        }
        return "Remove this wallpaper"
    }
}
