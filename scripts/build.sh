#!/usr/bin/env bash
# Builds Bendable and copies the app into build/.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-build}"
ARCHS="${ARCHS:-arm64}"
APP_VERSION="${MARKETING_VERSION:-$(scripts/version.sh)}"

echo "Building Bendable $APP_VERSION ($CONFIGURATION, $ARCHS)"
xcodebuild \
    -project Bendable.xcodeproj \
    -scheme Bendable \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$ARCHS" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$APP_VERSION" \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-YES}" \
    build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Bendable.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "error: $APP_PATH was not produced" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/Bendable.app"
cp -R "$APP_PATH" "$OUTPUT_DIR/Bendable.app"

# Code signing needs extended attributes and POSIX ownership. Building or staging on
# a filesystem without them (exFAT, FAT32, some network mounts) produces a bundle that
# will not launch, and the failure is otherwise cryptic.
if ! codesign --verify --deep "$OUTPUT_DIR/Bendable.app" 2>/dev/null; then
    echo "error: the copied bundle is not correctly signed." >&2
    echo "       This usually means DERIVED_DATA or OUTPUT_DIR is on a filesystem" >&2
    echo "       without extended attribute support. Set them to a path on an APFS" >&2
    echo "       volume, for example:" >&2
    echo "         DERIVED_DATA=/tmp/bendable-build OUTPUT_DIR=/tmp/bendable scripts/build.sh" >&2
    exit 1
fi

echo "Built $OUTPUT_DIR/Bendable.app"
