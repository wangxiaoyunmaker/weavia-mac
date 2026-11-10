#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}"
SOURCE="$ROOT/BrandAssets/weavia-original.png"
ICONSET="$ROOT/BrandAssets/WEAVIA.iconset"
mkdir -p "$ICONSET"
# Format conversion only: preserve the complete user-provided image, white background,
# proportions and colors. No redrawing, cropping, background removal or added styling.
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
  size="${spec%%:*}"
  name="${spec#*:}"
  /usr/bin/sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${name}.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT/BrandAssets/WEAVIA.icns"
echo "$ROOT/BrandAssets/WEAVIA.icns"
