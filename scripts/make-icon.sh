#!/usr/bin/env bash
# Regenerates the app icon and every size in the asset catalogue.
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="Bendable/Resources/Assets.xcassets/AppIcon.appiconset"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O scripts/make-icon.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/icon.png"

python3 - "$WORK/icon.png" "$ICONSET" <<'PY'
import json, os, subprocess, sys

source, destination = sys.argv[1], sys.argv[2]
specs = [
    (16, "16x16", "1x"), (32, "16x16", "2x"),
    (32, "32x32", "1x"), (64, "32x32", "2x"),
    (128, "128x128", "1x"), (256, "128x128", "2x"),
    (256, "256x256", "1x"), (512, "256x256", "2x"),
    (512, "512x512", "1x"), (1024, "512x512", "2x"),
]
images = []
for pixels, size, scale in specs:
    name = f"icon_{size}_{scale}.png"
    subprocess.run(
        ["sips", "-z", str(pixels), str(pixels), source, "--out", os.path.join(destination, name)],
        check=True, capture_output=True,
    )
    images.append({"filename": name, "idiom": "mac", "scale": scale, "size": size})

with open(os.path.join(destination, "Contents.json"), "w") as handle:
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, handle, indent=2)
PY

echo "Regenerated $ICONSET"
