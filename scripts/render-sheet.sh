#!/usr/bin/env bash
# Renders a preset across its whole travel to a PNG contact sheet, for checking
# geometry changes without opening and closing a laptop.
#
#   scripts/render-sheet.sh [preset-id] [output.png]
set -euo pipefail

cd "$(dirname "$0")/.."

PRESET="${1:-fold}"
OUTPUT="${2:-build/snapshots/$PRESET.png}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"

xcodebuild \
    -project Bendable.xcodeproj \
    -scheme Bendable \
    -configuration Debug \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_REQUIRED=NO \
    build >/dev/null

mkdir -p "$(dirname "$OUTPUT")"
"$DERIVED_DATA/Build/Products/Debug/Bendable.app/Contents/MacOS/Bendable" \
    --render-sheet "$PRESET" "$OUTPUT"
