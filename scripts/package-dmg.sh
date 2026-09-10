#!/usr/bin/env bash
# Packages build/Bendable.app into build/releases/Bendable.dmg.
#
# Run scripts/build.sh first, or pass an existing bundle as the first argument.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="${1:-${OUTPUT_DIR:-build}/Bendable.app}"
VOLUME_NAME="Bendable"
RELEASE_DIR="${RELEASE_DIR:-build/releases}"
DMG_PATH="$RELEASE_DIR/Bendable.dmg"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH not found. Run scripts/build.sh first." >&2
    exit 1
fi

# Staging happens in a temporary directory rather than the build tree: the image must
# be assembled on a filesystem that preserves extended attributes and ownership.
WORK_DIR="$(mktemp -d)"
STAGING_DIR="$WORK_DIR/staging"
TEMP_DMG="$WORK_DIR/Bendable-rw.dmg"
trap 'rm -rf "$WORK_DIR"' EXIT

rm -f "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$STAGING_DIR" "$RELEASE_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/Bendable.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Quarantine flags picked up from the build tree would otherwise travel inside the
# image. The code signature itself lives in the bundle, not in xattrs, so this is safe.
xattr -dr com.apple.quarantine "$STAGING_DIR/Bendable.app" 2>/dev/null || true

hdiutil create \
    -srcfolder "$STAGING_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$TEMP_DMG" >/dev/null

MOUNT_DIR="$(mktemp -d)"
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noautoopen >/dev/null

# Best effort: a headless machine has no Finder to talk to, and the image is still
# perfectly usable without the window arrangement.
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 160, 800, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set position of item "Bendable.app" of container window to {150, 190}
        set position of item "Applications" of container window to {450, 190}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
then
    echo "Applied Finder layout"
else
    echo "Skipped Finder layout (no window server)"
fi

sync
hdiutil detach "$MOUNT_DIR" >/dev/null || hdiutil detach "$MOUNT_DIR" -force >/dev/null
rmdir "$MOUNT_DIR" 2>/dev/null || true

hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null

codesign --verify --deep --strict "$APP_PATH" || {
    echo "error: $APP_PATH is not correctly signed" >&2
    exit 1
}

shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
echo "Packaged $DMG_PATH"
