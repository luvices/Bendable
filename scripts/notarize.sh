#!/usr/bin/env bash
# Signs and notarizes a DMG. Only used by the release workflow, and only when the
# optional signing secrets are configured; CI works without any of this.
#
# Required environment:
#   SIGNING_IDENTITY        Developer ID Application: ... (already in the keychain)
#   NOTARY_APPLE_ID         Apple ID used for notarytool
#   NOTARY_PASSWORD         App-specific password
#   NOTARY_TEAM_ID          Team identifier
set -euo pipefail

cd "$(dirname "$0")/.."

APP_PATH="${1:-build/Bendable.app}"
DMG_PATH="${2:-build/releases/Bendable.dmg}"

: "${SIGNING_IDENTITY:?SIGNING_IDENTITY is required}"
: "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID is required}"
: "${NOTARY_PASSWORD:?NOTARY_PASSWORD is required}"
: "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID is required}"

codesign --force --deep --options runtime --timestamp \
    --entitlements Bendable/Resources/Bendable.entitlements \
    --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

scripts/package-dmg.sh "$APP_PATH"

codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" \
    --wait

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "Signed, notarized and stapled $DMG_PATH"
