#!/usr/bin/env bash
# Runs the unit tests.
set -euo pipefail

cd "$(dirname "$0")/.."

xcodebuild \
    -project Bendable.xcodeproj \
    -scheme Bendable \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA:-build/DerivedData}" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO \
    test
