#!/usr/bin/env bash
# Builds TLS.app in Release and Debug and packages both as DMGs:
#   dist/TLS-<version>.dmg        normal use
#   dist/TLS-<version>-debug.dmg  development (Safari Web Inspector, debug hooks)
# Run apps/macos/scripts/prepare-artifacts.sh and scripts/tls/build-demo-snapshot.sh first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MAC="$ROOT/apps/macos"
DIST="$ROOT/dist"
VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' "$MAC/project.yml")"
mkdir -p "$DIST"

[ -f "$MAC/build/artifacts/demo/pgdata.tar.gz" ] || { echo "Falta la instantánea de la demo: scripts/tls/build-demo-snapshot.sh"; exit 1; }
command -v xcodegen >/dev/null && (cd "$MAC" && xcodegen generate --quiet)

package() {
  local config="$1" name="$2"
  echo "==> $config"
  xcodebuild -project "$MAC/TLS.xcodeproj" -scheme TLS -configuration "$config" \
    -derivedDataPath "$MAC/build/DerivedData" -destination 'platform=macOS,arch=arm64' clean build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
  local app="$MAC/build/DerivedData/Build/Products/$config/TLS.app"
  codesign --verify --deep --strict "$app"
  local stage
  stage="$(mktemp -d /tmp/tls-dmg.XXXXXX)"
  cp -R "$app" "$stage/TLS.app"
  ln -s /Applications "$stage/Aplicaciones"
  cat >"$stage/LEEME.txt" <<EOF
TLS $VERSION$( [ "$config" = Debug ] && echo " (debug)" )

1. Arrastra TLS a Aplicaciones.
2. La primera vez macOS la bloqueará (firmada para desarrollo, no notarizada):
   Ajustes del Sistema > Privacidad y seguridad > "Abrir igualmente",
   o en Terminal:  xattr -dr com.apple.quarantine /Applications/TLS.app
3. Abre TLS. Arranca su base de datos y su servidor y entra en la demo.

Requisitos: Mac con Apple Silicon, macOS 13 o posterior.
Agentes (opcional): Claude Code instalado y con sesión iniciada.
Datos: ~/Library/Application Support/TLS · Registros: ~/Library/Logs/TLS
Carpeta de la empresa: ~/TLS Empresas
EOF
  rm -f "$DIST/$name"
  hdiutil create -volname "TLS $VERSION" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$DIST/$name" >/dev/null
  rm -rf "$stage"
  echo "    $DIST/$name ($(du -h "$DIST/$name" | cut -f1))"
}

package Release "TLS-$VERSION.dmg"
package Debug "TLS-$VERSION-debug.dmg"
(cd "$DIST" && shasum -a 256 TLS-"$VERSION"*.dmg > "SHA256SUMS-$VERSION.txt")
cat "$DIST/SHA256SUMS-$VERSION.txt"
