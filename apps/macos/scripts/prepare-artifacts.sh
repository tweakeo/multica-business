#!/usr/bin/env bash
# Builds the inputs the Xcode target embeds:
#   build/artifacts/renderer/            desktop renderer (packages/views + core + ui)
#   build/artifacts/bin/multica          Go CLI/daemon
#   build/artifacts/bin/multica-server   Go API server (embedded mode)
#   build/artifacts/bin/multica-migrate  database migrations (embedded mode)
#   build/artifacts/migrations/          SQL migrations read by multica-migrate
#   build/artifacts/postgres/            relocatable PostgreSQL 17 (arm64)
#   build/artifacts/demo/                demo snapshot (scripts/tls/build-demo-snapshot.sh)
# Requires the repo toolchain (Node + pnpm via corepack, Go). End users of the
# .app need none of these.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ART="$HERE/build/artifacts"
CACHE="$HERE/build/cache"
PG_VERSION="17.11.0"
PG_SHA1="3196e27ea7d3ce6ab11e12a88c90063866d43534"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

echo "==> Building desktop renderer (electron-vite)"
(cd "$ROOT/apps/desktop" && pnpm exec electron-vite build)

echo "==> Building Go binaries (CLI, server, migrations)"
VERSION="$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null || echo dev)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
mkdir -p "$ART/bin"
(cd "$ROOT/server" && export CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 &&
  go build -ldflags "-s -w -X main.version=$VERSION -X main.commit=$COMMIT" -o "$ART/bin/multica" ./cmd/multica &&
  go build -ldflags "-s -w -X main.version=$VERSION -X main.commit=$COMMIT" -o "$ART/bin/multica-server" ./cmd/server &&
  go build -ldflags "-s -w" -o "$ART/bin/multica-migrate" ./cmd/migrate)

if [ ! -x "$ART/postgres/bin/postgres" ]; then
  echo "==> Fetching relocatable PostgreSQL $PG_VERSION (zonky embedded binaries)"
  mkdir -p "$CACHE"
  JAR="$CACHE/embedded-postgres-binaries-darwin-arm64v8-$PG_VERSION.jar"
  [ -f "$JAR" ] || curl -sfL -o "$JAR" "https://repo1.maven.org/maven2/io/zonky/test/postgres/embedded-postgres-binaries-darwin-arm64v8/$PG_VERSION/embedded-postgres-binaries-darwin-arm64v8-$PG_VERSION.jar"
  echo "$PG_SHA1  $JAR" | shasum -a1 -c - >/dev/null
  rm -rf "$CACHE/pg" && mkdir -p "$CACHE/pg"
  (cd "$CACHE/pg" && unzip -q -o "$JAR" '*.txz' && mkdir -p root && tar -xJf ./*.txz -C root)
  # Keep arm64 only: halves the size of the universal binaries.
  find "$CACHE/pg/root" -type f | while read -r f; do
    if lipo -archs "$f" 2>/dev/null | grep -q x86_64; then
      lipo -thin arm64 "$f" -output "$f.thin" && mv "$f.thin" "$f"
    fi
  done
  rm -rf "$ART/postgres" && cp -R "$CACHE/pg/root" "$ART/postgres"
fi

rm -rf "$ART/renderer" "$ART/migrations"
cp -R "$ROOT/apps/desktop/out/renderer" "$ART/renderer"
# multica-migrate finds ../migrations relative to its executable.
cp -R "$ROOT/server/migrations" "$ART/migrations"
[ -f "$ART/demo/pgdata.tar.gz" ] || echo "!! No demo snapshot: run scripts/tls/build-demo-snapshot.sh to bundle the demo"
echo "==> Artifacts ready in $ART"
