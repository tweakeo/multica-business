#!/usr/bin/env bash
# Builds the inputs the Xcode target embeds:
#   build/artifacts/renderer/   desktop renderer (packages/views + core + ui)
#   build/artifacts/bin/multica Go CLI/daemon for the host architecture
# Requires the repo toolchain (Node + pnpm via corepack, Go). End users of the
# .app need none of these.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ART="$HERE/build/artifacts"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

echo "==> Building desktop renderer (electron-vite)"
(cd "$ROOT/apps/desktop" && pnpm exec electron-vite build)

echo "==> Building multica CLI (Go)"
VERSION="$(git -C "$ROOT" describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null || echo dev)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
mkdir -p "$ART/bin"
(cd "$ROOT/server" && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build \
  -ldflags "-s -w -X main.version=$VERSION -X main.commit=$COMMIT" \
  -o "$ART/bin/multica" ./cmd/multica)

rm -rf "$ART/renderer"
cp -R "$ROOT/apps/desktop/out/renderer" "$ART/renderer"
echo "==> Artifacts ready in $ART"
