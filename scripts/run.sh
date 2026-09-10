#!/usr/bin/env bash
# Builds Bendable, installs it over /Applications/Bendable.app and restarts it.
#
# Installing rather than launching in place is deliberate: Screen Recording is granted
# per bundle path, so running each build from a fresh DerivedData directory means
# granting it again every time.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-Release}"

# Code signing needs real extended attributes and POSIX ownership. exFAT fakes the
# first with AppleDouble sidecars and has none of the second, so a bundle built there
# will not sign. Divert the build to a temp directory when that is where we are.
MOUNT_POINT="$(df -P . | awk 'NR==2 {print $6}')"
FILESYSTEM="$(mount | awk -v mp="$MOUNT_POINT" '$3 == mp {print $4}' | tr -d '(,')"
case "$FILESYSTEM" in
    apfs | hfs) ;;
    *)
        export DERIVED_DATA="${DERIVED_DATA:-/tmp/bendable-build}"
        export OUTPUT_DIR="${OUTPUT_DIR:-/tmp/bendable-out}"
        echo "Checkout is on $FILESYSTEM, which cannot hold a signed bundle."
        echo "Building in $DERIVED_DATA instead."
        ;;
esac

CONFIGURATION="$CONFIGURATION" scripts/build.sh

APP="${OUTPUT_DIR:-build}/Bendable.app"

osascript -e 'quit app "Bendable"' 2>/dev/null || true
# Give the running copy a moment to release its status item before it is replaced.
sleep 1
pkill -x Bendable 2>/dev/null || true

rm -rf /Applications/Bendable.app
cp -R "$APP" /Applications/Bendable.app
open -a /Applications/Bendable.app

echo "Running /Applications/Bendable.app"
