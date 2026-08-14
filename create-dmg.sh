#!/usr/bin/env bash
# Build CasperFlow.app and wrap it in a drag-to-Applications DMG.
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
APP="$PKG/dist/CasperFlow.app"
STAGE="$PKG/dist/dmg-stage"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PKG/Resources/Info.plist")"
DMG="$PKG/dist/CasperFlow-${VERSION}.dmg"
VOLUME_NAME="CasperFlow"

"$PKG/build-app.sh"

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP" >&2
  exit 1
fi

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/CasperFlow.app"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/Install.txt" <<'EOF'
CasperFlow — install

1. Drag CasperFlow into Applications.
2. Open CasperFlow from Applications (not this disk image).
3. First launch: if macOS blocks it, right-click the app → Open.
4. Grant Microphone and Accessibility (CasperFlow.app, not Cursor).
5. In the app, open API Keys and save your PyAI key (OpenAI is optional).

You do not need to clone the repo or run any scripts.
EOF

rm -f "$DMG" "$PKG/dist/CasperFlow.dmg"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

ln -sf "$(basename "$DMG")" "$PKG/dist/CasperFlow.dmg"
rm -rf "$STAGE"

echo
echo "DMG ready: $DMG"
echo "Give users that file. They drag CasperFlow → Applications, then set keys in the app."
echo
echo "Note: this build is ad-hoc signed. First open may need right-click → Open"
echo "(Apple notarization requires an Apple Developer ID)."
