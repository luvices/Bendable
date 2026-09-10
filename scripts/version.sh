#!/usr/bin/env bash
# Prints the version Bendable reports about itself.
#
# The Xcode project is the only place it is written down. Everything that needs it
# (the release workflow, the DMG name) reads it from here, so a bump is one edit.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(
    awk -F'[=;]' '/MARKETING_VERSION/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' \
        Bendable.xcodeproj/project.pbxproj
)"

if [[ -z "$VERSION" ]]; then
    echo "error: no MARKETING_VERSION in Bendable.xcodeproj/project.pbxproj" >&2
    exit 1
fi

echo "$VERSION"
