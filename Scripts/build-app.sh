#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AerialDrop"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

printf 'Building %s from a clean cache…\n' "$APP_NAME"
rm -rf .build
swift build -c release

VERSION=$(sed -n 's/.*static let shortVersion = "\([^"]*\)".*/\1/p' Sources/AerialDrop/AppVersion.swift)
BUILD_NUMBER=$(sed -n 's/.*static let buildNumber = "\([^"]*\)".*/\1/p' Sources/AerialDrop/AppVersion.swift)
if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
    echo "Could not read the version or build number from Sources/AerialDrop/AppVersion.swift" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>AerialDrop</string>
    <key>CFBundleExecutable</key>
    <string>AerialDrop</string>
    <key>CFBundleIdentifier</key>
    <string>com.yapwh.aerialdrop</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AerialDrop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
printf '\nCreated: %s\n' "$PWD/$APP_DIR"
printf 'Open a new instance with: open -n "%s"\n' "$PWD/$APP_DIR"
