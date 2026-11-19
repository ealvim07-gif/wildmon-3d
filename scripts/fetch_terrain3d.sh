#!/usr/bin/env bash
set -euo pipefail

VERSION="v1.0.2-stable"
URL="https://github.com/TokisanGames/Terrain3D/releases/download/${VERSION}/Terrain3D_v1.0.2-stable.zip"
EXPECTED_SHA256="a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2"
TMP_DIR="${RUNNER_TEMP:-/tmp}/wildmon-terrain3d"
ZIP="${TMP_DIR}/terrain3d.zip"
EXTRACTED="${TMP_DIR}/extracted"

mkdir -p "$TMP_DIR" "$EXTRACTED" addons
curl --fail --location --retry 3 "$URL" --output "$ZIP"
echo "$EXPECTED_SHA256  $ZIP" | sha256sum --check
unzip -q "$ZIP" -d "$EXTRACTED"

SOURCE="$EXTRACTED/addons/terrain_3d"
DEST="addons/terrain_3d"
test -s "$SOURCE/terrain.gdextension"
test -s "$SOURCE/bin/libterrain.android.release.arm64.so"
test -s "$SOURCE/bin/libterrain.android.debug.arm64.so"
test -s "$SOURCE/bin/libterrain.linux.release.x86_64.so"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SOURCE/." "$DEST/"
echo "Terrain3D ${VERSION} installed. Android ARM64 release/debug and Linux binaries verified."
du -sh "$DEST"
