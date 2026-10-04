#!/bin/sh
# Sourced by both build entry points before removing generated output.

aerialdrop_select_xcode() {
    if [ -n "${DEVELOPER_DIR:-}" ]; then
        aerialdrop_developer_dir="$DEVELOPER_DIR"
    elif aerialdrop_developer_dir="$(xcode-select -p)"; then
        case "$aerialdrop_developer_dir" in
            */CommandLineTools|*/CommandLineTools/)
                aerialdrop_developer_dir="/Applications/Xcode.app/Contents/Developer"
                ;;
        esac
    else
        printf '%s\n' 'Could not determine the active Xcode installation. Set DEVELOPER_DIR to a full Xcode installation and retry.' >&2
        return 1
    fi

    # DEVELOPER_DIR also accepts the path to an Xcode app bundle.
    if [ -d "$aerialdrop_developer_dir/Contents/Developer" ]; then
        aerialdrop_developer_dir="$aerialdrop_developer_dir/Contents/Developer"
    fi

    if [ ! -x "$aerialdrop_developer_dir/usr/bin/xcodebuild" ] ||
       [ ! -d "$aerialdrop_developer_dir/Platforms/MacOSX.platform/Developer/SDKs" ]; then
        printf 'Full Xcode with the macOS SDK is required. Cannot use: %s\n' "$aerialdrop_developer_dir" >&2
        printf '%s\n' 'Install Xcode or set DEVELOPER_DIR to its Contents/Developer directory, then retry. Build output has been preserved.' >&2
        return 1
    fi

    export DEVELOPER_DIR="$aerialdrop_developer_dir"
    printf 'Using Xcode: %s\n' "$DEVELOPER_DIR"
}

aerialdrop_select_xcode
