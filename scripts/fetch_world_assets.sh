#!/usr/bin/env bash
set -euo pipefail

DEST="assets/nature"
BASE="https://raw.githubusercontent.com/agentkaerf/FreeModels/main/Stylized%20Nature%20MegaKit%5BStandard%5D/glTF"
GOBKIT="https://gobkit.com/freebies"
mkdir -p "$DEST" assets/gobkit

# Quaternius Stylized Nature MegaKit Standard — CC0.
FILES=(
  CommonTree_1.gltf CommonTree_1.bin CommonTree_2.gltf CommonTree_2.bin
  CommonTree_3.gltf CommonTree_3.bin Pine_1.gltf Pine_1.bin Pine_2.gltf Pine_2.bin
  Bush_Common.gltf Bush_Common.bin Fern_1.gltf Fern_1.bin
  Rock_Medium_1.gltf Rock_Medium_1.bin Rock_Medium_2.gltf Rock_Medium_2.bin
  Clover_1.gltf Clover_1.bin Grass_Common_Tall.gltf Grass_Common_Tall.bin
  Flower_3_Group.gltf Flower_3_Group.bin Bark_NormalTree.png Bark_NormalTree_Normal.png
  Leaves_NormalTree_C.png Leaf_Pine_C.png Leaves_TwistedTree_C.png Leaves.png
  Rocks_Diffuse.png Flowers.png Grass.png
)
for file in "${FILES[@]}"; do
  echo "Downloading Quaternius $file"
  curl --fail --location --retry 3 --silent --show-error "$BASE/$file" --output "$DEST/$file"
  test -s "$DEST/$file"
done

# Gobkit selected CC0 GLB nature props: deliberately curated for the valley.
NATURE_MODELS=(Bush001 Bush002 Cliff001 Cliff002 Cloud001 Grass001 Grass002 Hill001
  MountainFar001 Reed001 Reed002 Rock001 Rock002 Rock003 TreeHigh001 TreeHigh002 TreeHigh003)
for model in "${NATURE_MODELS[@]}"; do
  echo "Downloading Gobkit nature $model"
  curl --fail --location --retry 3 --silent --show-error \
    "$GOBKIT/environment/$model.glb" --output "assets/gobkit/$model.glb"
  test -s "assets/gobkit/$model.glb"
done

# A small set of CC0 animated animals reserved for future wild encounters.
ANIMAL_MODELS=(Fox Doe Squirrel Hedgehog Hare Owl)
for model in "${ANIMAL_MODELS[@]}"; do
  echo "Downloading Gobkit creature $model"
  curl --fail --location --retry 3 --silent --show-error \
    "$GOBKIT/animal006/$model.glb" --output "assets/gobkit/$model.glb"
  test -s "assets/gobkit/$model.glb"
done

cat > "$DEST/ASSET-LICENSE.txt" <<'EOF'
Quaternius — Stylized Nature MegaKit (Standard assets)
License: CC0 1.0 Universal.
Source mirror: https://github.com/agentkaerf/FreeModels
Original pack: https://quaternius.com/packs/stylizednaturemegakit

Gobkit selected environment and animal GLB assets
License: CC0 1.0 Universal (public domain dedication).
Source and manifest: https://gobkit.com/freebies and https://gobkit.com/api/free
Only the explicitly listed GLB files are downloaded by this script.
EOF
echo "Downloaded ${#FILES[@]} Quaternius files plus Gobkit environment and creature assets."
