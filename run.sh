#!/usr/bin/env bash
# Launch the packaged .app via `open` so TCC/Accessibility binds to CasperFlow.app
# (not the parent terminal / Cursor).
set -euo pipefail

PKG="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$PKG/.." && pwd)"
APP="$PKG/dist/CasperFlow.app"

if [[ -f "$ROOT/.env" ]]; then
  KEY_LINE="$(grep -E '^PYAI_API_KEY=' "$ROOT/.env" | tail -n1 || true)"
  if [[ -n "$KEY_LINE" ]]; then
    export PYAI_API_KEY="${KEY_LINE#PYAI_API_KEY=}"
  fi
fi

if [[ -z "${PYAI_API_KEY:-}" ]]; then
  echo "PYAI_API_KEY is not set. Add it to $ROOT/.env or export it." >&2
  exit 1
fi

NEED_BUILD=0
if [[ ! -d "$APP" ]]; then
  NEED_BUILD=1
else
  BIN_SRC="$(cd "$PKG" && swift build -c release --show-bin-path 2>/dev/null)/CasperFlow"
  if [[ ! -x "$BIN_SRC" ]] || [[ "$PKG/Sources/CasperFlow" -nt "$APP/Contents/MacOS/CasperFlow" ]]; then
    NEED_BUILD=1
  fi
fi

if [[ "$NEED_BUILD" -eq 1 ]]; then
  "$PKG/build-app.sh"
fi

# Kill previous instance so Accessibility toggle applies cleanly.
pkill -x CasperFlow 2>/dev/null || true
sleep 0.3

# `open` registers the .app with TCC. App also reads ../.env via ApiKeyStore.
# Pass key for this launch when supported (macOS 13+).
if open --help 2>&1 | grep -q -- '--env'; then
  open "$APP" --env "PYAI_API_KEY=$PYAI_API_KEY"
else
  # Fallback: key still loaded from repo .env inside the app.
  open "$APP"
fi

echo "Launched $APP"
echo "In Accessibility, enable CasperFlow (bundle com.casperflow.app) — not Cursor."
