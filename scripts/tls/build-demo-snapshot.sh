#!/usr/bin/env bash
# Freezes the current demo into the artifacts TLS.app bundles for first launch
# on another Mac (no restore tools needed there):
#   apps/macos/build/artifacts/demo/pgdata.tar.gz  initialised cluster (bundled
#                                                  PostgreSQL), credentials removed
#   apps/macos/build/artifacts/demo/folder.tar.gz  the demo company folder
# Requires the local dev database (Homebrew PostgreSQL 17) with the demo seeded
# and apps/macos/scripts/prepare-artifacts.sh run before (bundled PostgreSQL).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ART="$ROOT/apps/macos/build/artifacts"
PG="$ART/postgres"
BREW="/opt/homebrew/opt/postgresql@17/bin"
DEV_URL="${DATABASE_URL:-postgres://multica:multica@localhost:5432/multica?sslmode=disable}"
# Company folder of the dev database (where the seed wrote it).
FOLDER="$("$BREW/psql" "$DEV_URL" -Atc "SELECT value #>> '{}' FROM biz_setting WHERE key='company_folder' LIMIT 1")"
WORK="$(mktemp -d /tmp/tls-snapshot.XXXXXX)"
trap '"$PG/bin/pg_ctl" -D "$WORK/data" stop -m fast >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

[ -x "$PG/bin/postgres" ] || { echo "Falta $PG: ejecuta prepare-artifacts.sh"; exit 1; }
[ -d "$FOLDER" ] || { echo "Falta la carpeta de la demo: $FOLDER"; exit 1; }

echo "==> Volcando la base de datos de desarrollo"
"$BREW/pg_dump" -Fc --no-owner --no-privileges -f "$WORK/demo.dump" "$DEV_URL"

echo "==> Inicializando el clúster con el PostgreSQL empaquetado"
"$PG/bin/initdb" -D "$WORK/data" -U multica -A trust -E UTF8 --locale=C >/dev/null
"$PG/bin/pg_ctl" -D "$WORK/data" -o "-c listen_addresses='' -k $WORK" -l "$WORK/pg.log" -w start >/dev/null
SOCK="postgres://multica@/postgres?host=$WORK"
"$BREW/psql" "$SOCK" -qc "CREATE DATABASE multica"
"$BREW/pg_restore" --no-owner --no-privileges -d "postgres://multica@/multica?host=$WORK" "$WORK/demo.dump" 2>"$WORK/restore.log" || {
  grep -v "already exists" "$WORK/restore.log" | head -20
}

echo "==> Quitando credenciales, sesiones y restos de pruebas"
"$BREW/psql" "postgres://multica@/multica?host=$WORK" -q <<'SQL'
DELETE FROM personal_access_token;
DELETE FROM daemon_token;
DELETE FROM daemon_connection;
DELETE FROM task_token;
DELETE FROM verification_code;
DELETE FROM channel_binding_token;
DELETE FROM lark_binding_token;
DELETE FROM plugin_secret;
DELETE FROM user_composio_connection;
DELETE FROM vcs_connection;
DELETE FROM "user" u WHERE NOT EXISTS (SELECT 1 FROM member m WHERE m.user_id = u.id);
-- Home-relative path: the folder lands in the new user's home.
UPDATE biz_setting SET value = to_jsonb('~/TLS Empresas/DEMO - Asesoría Ribera'::text) WHERE key = 'company_folder';
SQL
"$PG/bin/pg_ctl" -D "$WORK/data" stop -m fast >/dev/null

mkdir -p "$ART/demo"
tar -czf "$ART/demo/pgdata.tar.gz" -C "$WORK" data
# The bundle always restores it as ~/TLS Empresas/DEMO - Asesoría Ribera.
mkdir -p "$WORK/folder" && cp -R "$FOLDER" "$WORK/folder/DEMO - Asesoría Ribera"
tar -czf "$ART/demo/folder.tar.gz" -C "$WORK/folder" "DEMO - Asesoría Ribera"
du -sh "$ART/demo/"*
echo "==> Instantánea de la demo lista"
