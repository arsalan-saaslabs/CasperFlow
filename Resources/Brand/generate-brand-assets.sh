#!/usr/bin/env bash
# Rasterize Casper brand SVGs into AppIcon.icns and menu-bar PNGs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRAND="$ROOT/Resources/Brand"
ICONSET="$BRAND/AppIcon.appiconset"
MENUSET="$BRAND/CasperMenuBar.imageset"
OUT_ICNS="$ROOT/Resources/AppIcon.icns"

rm -rf "$ICONSET" "$MENUSET"
mkdir -p "$ICONSET" "$MENUSET"

rasterize() {
  local svg="$1"
  local px="$2"
  local dest="$3"
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$px" -h "$px" "$svg" -o "$dest"
  elif command -v magick >/dev/null 2>&1; then
    magick -background none -density 384 "$svg" -resize "${px}x${px}" "$dest"
  else
    local tmp
    tmp="$(mktemp -d)"
    qlmanage -t -s "$px" -o "$tmp" "$svg" >/dev/null
    local produced
    produced="$(find "$tmp" -name '*.png' | head -n 1)"
    sips -z "$px" "$px" "$produced" --out "$dest" >/dev/null
    rm -rf "$tmp"
  fi
}

# App icon sizes (Xcode slot → pixels)
declare -a SIZES=(16 32 32 64 128 256 256 512 512 1024)
declare -a NAMES=(
  "icon_16x16.png"
  "icon_16x16@2x.png"
  "icon_32x32.png"
  "icon_32x32@2x.png"
  "icon_128x128.png"
  "icon_128x128@2x.png"
  "icon_256x256.png"
  "icon_256x256@2x.png"
  "icon_512x512.png"
  "icon_512x512@2x.png"
)

for i in "${!SIZES[@]}"; do
  rasterize "$BRAND/casper-app-icon.svg" "${SIZES[$i]}" "$ICONSET/${NAMES[$i]}"
done

cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images": [
    { "idiom": "mac", "size": "16x16", "scale": "1x", "filename": "icon_16x16.png" },
    { "idiom": "mac", "size": "16x16", "scale": "2x", "filename": "icon_16x16@2x.png" },
    { "idiom": "mac", "size": "32x32", "scale": "1x", "filename": "icon_32x32.png" },
    { "idiom": "mac", "size": "32x32", "scale": "2x", "filename": "icon_32x32@2x.png" },
    { "idiom": "mac", "size": "128x128", "scale": "1x", "filename": "icon_128x128.png" },
    { "idiom": "mac", "size": "128x128", "scale": "2x", "filename": "icon_128x128@2x.png" },
    { "idiom": "mac", "size": "256x256", "scale": "1x", "filename": "icon_256x256.png" },
    { "idiom": "mac", "size": "256x256", "scale": "2x", "filename": "icon_256x256@2x.png" },
    { "idiom": "mac", "size": "512x512", "scale": "1x", "filename": "icon_512x512.png" },
    { "idiom": "mac", "size": "512x512", "scale": "2x", "filename": "icon_512x512@2x.png" }
  ],
  "info": { "version": 1, "author": "casper" }
}
EOF

iconutil -c icns "$ICONSET" -o "$OUT_ICNS"

rasterize "$BRAND/casper-menubar-template.svg" 18 "$MENUSET/casper-menubar.png"
rasterize "$BRAND/casper-menubar-template.svg" 36 "$MENUSET/casper-menubar@2x.png"
rasterize "$BRAND/casper-menubar-template.svg" 54 "$MENUSET/casper-menubar@3x.png"

cat > "$MENUSET/Contents.json" <<'EOF'
{
  "images": [
    { "idiom": "mac", "scale": "1x", "filename": "casper-menubar.png" },
    { "idiom": "mac", "scale": "2x", "filename": "casper-menubar@2x.png" },
    { "idiom": "mac", "scale": "3x", "filename": "casper-menubar@3x.png" }
  ],
  "info": { "version": 1, "author": "casper" },
  "properties": { "template-rendering-intent": "template" }
}
EOF

cp "$MENUSET/casper-menubar.png" "$ROOT/Resources/CasperMenuBar.png"
cp "$MENUSET/casper-menubar@2x.png" "$ROOT/Resources/CasperMenuBar@2x.png"
cp "$MENUSET/casper-menubar@3x.png" "$ROOT/Resources/CasperMenuBar@3x.png"

echo "Wrote $OUT_ICNS and menu-bar PNGs"
