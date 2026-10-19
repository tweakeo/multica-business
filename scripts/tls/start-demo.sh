#!/usr/bin/env bash
# Development mode with an external server: PostgreSQL (Homebrew) → Go
# backend on :8080 (logs in ~/Library/Logs/TLS) → TLS.app switched to
# "external" mode. The installable app (DMG) uses embedded mode instead; to
# go back, set "mode": "embedded" in ~/Library/Application Support/TLS/runtime-config.json.
#   scripts/tls/start-demo.sh          # start
#   scripts/tls/start-demo.sh stop     # stop the backend (database keeps running)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOGS="$HOME/Library/Logs/TLS"
PIDFILE="$LOGS/backend.pid"
mkdir -p "$LOGS"

if [ "${1:-}" = "stop" ]; then
  if [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null; then echo "Backend detenido."; else echo "El backend no estaba en marcha."; fi
  rm -f "$PIDFILE"
  exit 0
fi

echo "==> PostgreSQL"
brew services start postgresql@17 >/dev/null 2>&1 || true
for _ in $(seq 1 30); do /opt/homebrew/opt/postgresql@17/bin/pg_isready -q && break; sleep 1; done

if curl -sf -o /dev/null http://localhost:8080/health; then
  echo "==> Backend ya en marcha en :8080"
else
  echo "==> Backend (log: $LOGS/backend.log)"
  nohup "$ROOT/scripts/tls/run-backend.sh" >"$LOGS/backend.log" 2>&1 &
  echo $! >"$PIDFILE"
  for _ in $(seq 1 120); do curl -sf -o /dev/null http://localhost:8080/health && break; sleep 1; done
  curl -sf -o /dev/null http://localhost:8080/health || { echo "El backend no arrancó; revisa $LOGS/backend.log"; exit 1; }
fi

CONFIG="$HOME/Library/Application Support/TLS/runtime-config.json"
mkdir -p "$(dirname "$CONFIG")"
cat >"$CONFIG" <<'JSON'
{ "schemaVersion": 1, "mode": "external", "apiUrl": "http://localhost:8080", "wsUrl": "ws://localhost:8080/ws", "appUrl": "http://localhost:3000" }
JSON

APP="$ROOT/apps/macos/build/DerivedData/Build/Products/Release/TLS.app"
[ -d "$APP" ] || APP="$ROOT/apps/macos/build/DerivedData/Build/Products/Debug/TLS.app"
if [ ! -d "$APP" ]; then
  echo "No hay TLS.app compilada: ejecuta apps/macos/scripts/build.sh"
  exit 1
fi
echo "==> Abriendo $APP"
open "$APP"
