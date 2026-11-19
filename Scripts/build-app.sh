#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")/.."

. "$PWD/Scripts/select-xcode.sh" || exit $?

APP_NAME="AerialDrop"
BUILD_DIR=".build/release"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
FRAMEWORKS_DIR="$CONTENTS/Frameworks"

UPDATE_PUBLIC_KEY="${AERIALDROP_UPDATE_PUBLIC_KEY:-}"
if [[ -n "$UPDATE_PUBLIC_KEY" && ! "$UPDATE_PUBLIC_KEY" =~ '^[A-Za-z0-9+/]{43}=$' ]]; then
    echo "AERIALDROP_UPDATE_PUBLIC_KEY must be a base64-encoded 32-byte Ed25519 public key" >&2
    exit 1
fi

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
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# SwiftPM extracts the signed macOS framework from Sparkle's binary artifact.
SPARKLE_FRAMEWORK=$(find .build/artifacts -path '*/macos-arm64_x86_64/Sparkle.framework' -type d -print -quit)
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "Could not find the macOS Sparkle framework in SwiftPM artifacts" >&2
    exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
cp .build/checkouts/Sparkle/LICENSE "$RESOURCES_DIR/Sparkle-LICENSE.txt"
codesign --verify --deep --strict --verbose=2 "$FRAMEWORKS_DIR/Sparkle.framework"

if [[ -f "$PWD/Assets/AppIcon.icns" ]]; then
    cp "$PWD/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
else
    echo "Warning: Assets/AppIcon.icns not found; run Scripts/make-icon.swift first" >&2
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>AerialDrop</string>
    <key>CFBundleExecutable</key>
    <string>AerialDrop</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

if [[ -n "$UPDATE_PUBLIC_KEY" ]]; then
    PLIST_BUDDY=/usr/libexec/PlistBuddy
    "$PLIST_BUDDY" -c "Add :SUPublicEDKey string $UPDATE_PUBLIC_KEY" "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c "Add :SUFeedURL string https://github.com/YapWH1208/AerialDrop/releases/latest/download/appcast.xml" "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c 'Add :SUEnableAutomaticChecks bool true' "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c 'Add :SUAllowsAutomaticUpdates bool false' "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c 'Add :SUEnableSystemProfiling bool false' "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c 'Add :SUVerifyUpdateBeforeExtraction bool true' "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c 'Add :SURequireSignedFeed bool true' "$CONTENTS/Info.plist"
    "$PLIST_BUDDY" -c 'Add :SUSignedFeedFailureExpirationInterval integer 0' "$CONTENTS/Info.plist"
fi
plutil -lint "$CONTENTS/Info.plist"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
printf '\nCreated: %s\n' "$PWD/$APP_DIR"
printf 'Open a new instance with: open -n "%s"\n' "$PWD/$APP_DIR"
