#!/usr/bin/env bash
# Launch the packaged .app via `open` so TCC/Accessibility binds to Casper.app
# (not the parent terminal / Cursor).
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
DIST_APP="$PKG/dist/Casper.app"
APP="${HOME}/Applications/Casper.app"

# Optional .env next to this script (never required — keys can be set in the app).
load_optional_env() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  line="$(grep -E '^PYAI_API_KEY=' "$file" | tail -n1 || true)"
  if [[ -n "$line" && -z "${PYAI_API_KEY:-}" ]]; then
    export PYAI_API_KEY="${line#PYAI_API_KEY=}"
    PYAI_API_KEY="${PYAI_API_KEY%\"}"
    PYAI_API_KEY="${PYAI_API_KEY#\"}"
    PYAI_API_KEY="${PYAI_API_KEY%\'}"
    PYAI_API_KEY="${PYAI_API_KEY#\'}"
    export PYAI_API_KEY
  fi
}

load_optional_env "$PKG/.env"

NEED_BUILD=0
if [[ ! -d "$DIST_APP" ]] || [[ ! -d "$APP" ]]; then
  NEED_BUILD=1
else
  BIN_SRC="$(cd "$PKG" && swift build -c release --show-bin-path 2>/dev/null)/CasperFlow"
  INSTALLED_BIN="$APP/Contents/MacOS/CasperFlow"
  if [[ ! -x "$BIN_SRC" ]] || [[ ! -x "$INSTALLED_BIN" ]]; then
    NEED_BUILD=1
  elif find "$PKG/Sources/CasperFlow" -name "*.swift" -newer "$INSTALLED_BIN" -print -quit | grep -q .; then
    NEED_BUILD=1
  fi
fi

if [[ "$NEED_BUILD" -eq 1 ]]; then
  "$PKG/build-app.sh"
fi

# Kill previous instance so Accessibility toggle applies cleanly.
pkill -x CasperFlow 2>/dev/null || true
sleep 0.3

# Prefer launching ~/Applications so Accessibility stays on the same bundle.
if [[ -n "${PYAI_API_KEY:-}" ]] && open --help 2>&1 | grep -q -- '--env'; then
  open "$APP" --env "PYAI_API_KEY=$PYAI_API_KEY"
else
  open "$APP"
fi

echo "Launched $APP"
if [[ -z "${PYAI_API_KEY:-}" ]]; then
  echo "No PYAI_API_KEY in the environment — set it in CasperFlow → API Keys if you have not already."
fi
echo "In Accessibility, enable Casper from ~/Applications (bundle com.casperflow.app) — not Cursor, not the Desktop/dist copy."
