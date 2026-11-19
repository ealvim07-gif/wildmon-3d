#!/usr/bin/env bash
set -euo pipefail

DEST="assets/nature"
BASE="https://raw.githubusercontent.com/agentkaerf/FreeModels/main/Stylized%20Nature%20MegaKit%5BStandard%5D/glTF"
mkdir -p "$DEST"

# CC0 models from the Quaternius Stylized Nature MegaKit Standard mirror.
FILES=(
  CommonTree_1.gltf CommonTree_1.bin
  CommonTree_2.gltf CommonTree_2.bin
  CommonTree_3.gltf CommonTree_3.bin
  Pine_1.gltf Pine_1.bin
  Pine_2.gltf Pine_2.bin
  Bush_Common.gltf Bush_Common.bin
  Fern_1.gltf Fern_1.bin
  Rock_Medium_1.gltf Rock_Medium_1.bin
  Rock_Medium_2.gltf Rock_Medium_2.bin
  Clover_1.gltf Clover_1.bin
  Grass_Common_Tall.gltf Grass_Common_Tall.bin
  Flower_3_Group.gltf Flower_3_Group.bin
  Bark_NormalTree.png Bark_NormalTree_Normal.png
  Leaves_NormalTree_C.png Leaf_Pine_C.png
  Leaves_TwistedTree_C.png Leaves.png
  Rocks_Diffuse.png Flowers.png Grass.png
)

for file in "${FILES[@]}"; do
  echo "Downloading $file"
  curl --fail --location --retry 3 --silent --show-error \
    "$BASE/$file" --output "$DEST/$file"
  test -s "$DEST/$file"
done

cat > "$DEST/ASSET-LICENSE.txt" <<'EOF'
Quaternius — Stylized Nature MegaKit (Standard assets)
License: CC0 1.0 Universal (public domain dedication)
Source mirror: https://github.com/agentkaerf/FreeModels
Original pack: https://quaternius.com/packs/stylizednaturemegakit
The included models and textures are from the free Standard subset.
EOF

echo "Downloaded ${#FILES[@]} Quaternius model/texture files into $DEST."
