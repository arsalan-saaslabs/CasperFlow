#!/usr/bin/env bash
# Build a real .app bundle so CasperFlow appears in System Settings → Accessibility.
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PKG/.." && pwd)"
APP_DIR="$PKG/dist/CasperFlow.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

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

# Ad-hoc sign so TCC / Accessibility can bind to this bundle id.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built: $APP_DIR"
echo "Bundle ID: com.casperflow.app"
echo
echo "Next:"
echo "  1) open \"$APP_DIR\""
echo "  2) When prompted, allow Accessibility (or System Settings → Privacy → Accessibility → + → pick CasperFlow.app)"
echo "  3) Enable the toggle for CasperFlow"
echo
echo "Tip: always launch THIS .app (not 'swift run'), or Accessibility won't list it."
