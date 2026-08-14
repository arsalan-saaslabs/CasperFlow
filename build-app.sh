#!/usr/bin/env bash
# Build a real .app bundle so CasperFlow appears in System Settings → Accessibility.
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PKG/dist/Casper.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
USER_APP="${HOME}/Applications/Casper.app"
BUNDLE_ID="com.casperflow.app"

sign_app() {
  local app="$1"
  # Identifier-based designated requirement so TCC survives rebuilds
  # (plain ad-hoc signing binds TCC to a cdhash that changes every build).
  codesign --force --deep --sign - \
    --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" \
    "$app"
  xattr -cr "$app" 2>/dev/null || true
}

echo "Building CasperFlow (release)…"
cd "$PKG"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/CasperFlow"
if [[ ! -x "$BIN" ]]; then
  echo "Binary not found at $BIN" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN" "$MACOS_DIR/CasperFlow"
cp "$PKG/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -f "$PKG/Resources/AppIcon.icns" ]]; then
  cp "$PKG/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi
if [[ -f "$PKG/Resources/Brand/casper-app-icon.png" ]]; then
  cp "$PKG/Resources/Brand/casper-app-icon.png" "$RES_DIR/CasperAppIcon.png"
fi
for f in CasperMenuBar.png CasperMenuBar@2x.png CasperMenuBar@3x.png; do
  if [[ -f "$PKG/Resources/$f" ]]; then
    cp "$PKG/Resources/$f" "$RES_DIR/$f"
  fi
done
sign_app "$APP_DIR"

mkdir -p "${HOME}/Applications"
rm -rf "$USER_APP"
# Finder shows the .app filename. Remove the old CasperFlow.app wrapper if present.
rm -rf "${HOME}/Applications/CasperFlow.app"
cp -R "$APP_DIR" "$USER_APP"
sign_app "$USER_APP"

echo "Built: $APP_DIR"
echo "Installed: $USER_APP"
echo "Bundle ID: $BUNDLE_ID"
echo
echo "Next:"
echo "  1) open \"$USER_APP\""
echo "  2) Accessibility → enable Casper in ~/Applications (not Cursor, not dist/)"
echo "  3) After a rebuild, that same toggle should keep working"
echo
echo "Tip: always launch THIS .app (not 'swift run'), or Accessibility won't list it."
