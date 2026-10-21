#!/usr/bin/env bash
# Production company "The Last", separate from the demo:
#   - its own PostgreSQL cluster (Unix socket only) in
#     ~/Library/Application Support/TLS/The Last/ — never inside iCloud;
#   - its own API on 127.0.0.1:8090 and web on http://localhost:3001;
#   - the company folder is $TLS_COMPANY_FOLDER (required).
# The demo keeps the dev database (multica), :8080/:3000 and ~/TLS Empresas/,
# so build-demo-snapshot.sh can never pick up real data.
#
#   scripts/tls/the-last.sh start    # cluster + migrations + API + web (builds on first run)
#   scripts/tls/the-last.sh setup    # first time: user, workspace, folder, rebuild (the-last-setup.mjs)
#   scripts/tls/the-last.sh decisiones  # import the lines of Decisiones.md (adds only the id mark)
#   scripts/tls/the-last.sh fechas [--apply]  # real dates of the documents into "4 · Finanzas/Fechas de documentos.csv"
#   scripts/tls/the-last.sh stop
#   scripts/tls/the-last.sh status
#   scripts/tls/the-last.sh build    # rebuild API and web after pulling changes
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STATE="$HOME/Library/Application Support/TLS/The Last"
PGDATA="$STATE/pgdata"
SOCK="$STATE/pg"
RUN="$STATE/run"
LOGS="$HOME/Library/Logs/TLS"
BREW="/opt/homebrew/opt/postgresql@17/bin"
API_PORT=8090
WEB_PORT=3001
export COMPANY_FOLDER="${TLS_COMPANY_FOLDER:?Define TLS_COMPANY_FOLDER con la carpeta de la empresa}"
mkdir -p "$STATE" "$SOCK" "$RUN" "$LOGS" "$STATE/uploads"
chmod 700 "$STATE" "$SOCK"

DB_URL="postgres://tls@/tls?host=$(node -p 'encodeURIComponent(process.argv[1])' "$SOCK")&sslmode=disable"

alive() { [ -f "$RUN/$1.pid" ] && kill -0 "$(cat "$RUN/$1.pid")" 2>/dev/null; }
wait_http() { for _ in $(seq 1 "${2:-120}"); do curl -sf -o /dev/null "$1" && return 0; sleep 1; done; return 1; }

secrets() {
  local f="$STATE/secrets.env"
  if [ ! -f "$f" ]; then
    umask 077
    printf 'JWT_SECRET=%s\nMULTICA_DEV_VERIFICATION_CODE=%06d\n' "$(openssl rand -hex 32)" "$((0x$(openssl rand -hex 3) % 1000000))" >"$f"
  fi
  echo "$f"
}

# Only what the server needs: nothing from the checkout's .env (dev DB, mail…).
server_env() {
  env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" \
    DATABASE_URL="$DB_URL" MULTICA_SECRETS_FILE="$(secrets)" APP_ENV=development \
    PORT="$API_PORT" BIND_HOST=127.0.0.1 \
    CORS_ALLOWED_ORIGINS="http://localhost:$WEB_PORT" FRONTEND_ORIGIN="http://localhost:$WEB_PORT" \
    MULTICA_PUBLIC_URL="http://127.0.0.1:$API_PORT" MULTICA_APP_URL="http://localhost:$WEB_PORT" \
    LOCAL_UPLOAD_DIR="$STATE/uploads" LOCAL_UPLOAD_BASE_URL="http://localhost:$WEB_PORT" \
    TLS_STATE_DIR="$HOME/Library/Application Support/TLS" \
    FF_PROJECT_WORKFLOWS_V1=true DO_NOT_TRACK=1 ANALYTICS_DISABLED=true "$@"
}

start_pg() {
  if [ ! -f "$PGDATA/PG_VERSION" ]; then
    echo "==> Creando la base de datos de The Last en $STATE"
    "$BREW/initdb" -D "$PGDATA" -U tls -A trust -E UTF8 --locale=C >"$LOGS/the-last-setup.log"
  fi
  if ! "$BREW/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
    LC_ALL=C "$BREW/pg_ctl" -D "$PGDATA" -o "-c listen_addresses='' -k '$SOCK' -c unix_socket_permissions=0700" \
      -l "$LOGS/the-last-postgres.log" -w -t 60 start >/dev/null
  fi
  "$BREW/psql" "postgres://tls@/postgres?host=$SOCK" -Atqc "SELECT 1 FROM pg_database WHERE datname='tls'" | grep -q 1 ||
    "$BREW/psql" "postgres://tls@/postgres?host=$SOCK" -qc "CREATE DATABASE tls"
}

build() {
  echo "==> Compilando API"
  (cd "$ROOT/server" && go build -o "$STATE/bin/multica-server" ./cmd/server && go build -o "$STATE/bin/multica-migrate" ./cmd/migrate)
  echo "==> Compilando web (apps/web/.next-the-last)"
  (cd "$ROOT/apps/web" && NEXT_DIST_DIR=.next-the-last REMOTE_API_URL="http://127.0.0.1:$API_PORT" pnpm exec next build --webpack >"$LOGS/the-last-web-build.log" 2>&1) ||
    { echo "La web no compiló; revisa $LOGS/the-last-web-build.log"; exit 1; }
}

start() {
  start_pg
  [ -x "$STATE/bin/multica-server" ] && [ -d "$ROOT/apps/web/.next-the-last" ] || build
  if ! alive api; then
    echo "==> Migraciones y API en :$API_PORT"
    server_env "$STATE/bin/multica-migrate" up >>"$LOGS/the-last-setup.log" 2>&1
    (cd "$STATE" && server_env nohup "$STATE/bin/multica-server" </dev/null >"$LOGS/the-last-server.log" 2>&1 & echo $! >"$RUN/api.pid")
    wait_http "http://127.0.0.1:$API_PORT/health" 120 || { echo "La API no arrancó; revisa $LOGS/the-last-server.log"; exit 1; }
  fi
  if ! alive web; then
    echo "==> Web en :$WEB_PORT"
    (cd "$ROOT/apps/web" && NEXT_DIST_DIR=.next-the-last REMOTE_API_URL="http://127.0.0.1:$API_PORT" \
      nohup pnpm exec next start --hostname 127.0.0.1 --port "$WEB_PORT" </dev/null >"$LOGS/the-last-web.log" 2>&1 & echo $! >"$RUN/web.pid")
    wait_http "http://localhost:$WEB_PORT" 120 || { echo "La web no arrancó; revisa $LOGS/the-last-web.log"; exit 1; }
  fi
  echo "The Last → http://localhost:$WEB_PORT (API :$API_PORT) · carpeta: $COMPANY_FOLDER"
}

killtree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do killtree "$c"; done; kill "$1" 2>/dev/null || true; }

case "${1:-start}" in
  start) start ;;
  build) start_pg; build ;;
  setup)
    start
    set -a; . "$(secrets)"; set +a
    TLS_API="http://127.0.0.1:$API_PORT" TLS_CODE="$MULTICA_DEV_VERIFICATION_CODE" node "$ROOT/scripts/tls/the-last-setup.mjs" "${@:2}"
    ;;
  decisiones)
    start
    set -a; . "$(secrets)"; set +a
    TLS_API="http://127.0.0.1:$API_PORT" TLS_CODE="$MULTICA_DEV_VERIFICATION_CODE" node "$ROOT/scripts/tls/the-last-decisiones.mjs"
    ;;
  fechas)
    COMPANY_FOLDER="$COMPANY_FOLDER" node "$ROOT/scripts/tls/the-last-fechas.mjs" "${@:2}"
    ;;
  stop)
    for p in web api; do alive "$p" && killtree "$(cat "$RUN/$p.pid")" && echo "$p detenido"; rm -f "$RUN/$p.pid"; done
    "$BREW/pg_ctl" -D "$PGDATA" stop -m fast >/dev/null 2>&1 && echo "PostgreSQL de The Last detenido" || true
    ;;
  status)
    curl -s -o /dev/null -w "api %{http_code}\n" "http://127.0.0.1:$API_PORT/health" || echo "api parada"
    curl -s -o /dev/null -w "web %{http_code}\n" "http://localhost:$WEB_PORT" || echo "web parada"
    "$BREW/pg_ctl" -D "$PGDATA" status 2>&1 | head -1
    ;;
  *) echo "uso: $0 {start|setup|decisiones|fechas|stop|status|build}"; exit 1 ;;
esac
