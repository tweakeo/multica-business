#!/bin/bash
# make verify (PLAN §10): firma de la app y de tls-mcp, permisos declarados, último DMG,
# sumas SHA-256, contenido del disco montado en solo lectura y prueba del sandbox (F1).
# Variables: DERIVED (build/DerivedData), DIST (dist), TLS_EXIGIR_FIRMA=1 (falla si es ad hoc)
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

DERIVED="${DERIVED:-build/DerivedData}"
DIST="${DIST:-dist}"
NOMBRE_APP="The Last System"
HELPER_REL="Contents/Helpers/tls-mcp"
APP="$DERIVED/Build/Products/Release/$NOMBRE_APP.app"

paso()  { printf '\n==> %s\n' "$*"; }
aviso() { printf 'AVISO: %s\n' "$*" >&2; }
fallo() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$APP" ]] || fallo "No hay app Release en $APP. Ejecuta antes: make dmg"

# Firma estricta de un paquete o binario y resumen de quién lo firmó.
comprobar() {
  local destino="$1" nombre="$2" info
  codesign --verify --deep --strict --verbose=2 "$destino" \
    || fallo "La firma de $nombre no verifica."
  info="$({ codesign -dv --verbose=2 "$destino" 2>&1 || true; })"
  { printf '%s\n' "$info" | grep -E '^(Identifier|Authority|TeamIdentifier|Signature)=|flags=' || true; } | sed 's/^/    /'
  if printf '%s\n' "$info" | grep -q '^Authority=Apple Development:'; then
    printf '%s\n' "$info" | grep -q 'flags=.*runtime' || fallo "$nombre no tiene el runtime reforzado (hardened runtime)."
    echo "    $nombre: Apple Development con runtime reforzado."
  else
    [[ "${TLS_EXIGIR_FIRMA:-0}" == 1 ]] && fallo "$nombre tiene firma ad hoc y TLS_EXIGIR_FIRMA=1."
    aviso "$nombre tiene firma ad hoc (sin equipo). Ejecuta make firma y vuelve a generar el DMG."
  fi
}

# Permisos declarados: los del plan (§3.1) y ninguno de los prohibidos.
permisos() {
  local destino="$1" nombre="$2" ent
  ent="$(codesign -d --entitlements - --xml "$destino" 2>/dev/null || true)"
  echo "    Permisos de $nombre:"
  printf '%s\n' "$ent" | plutil -p - 2>/dev/null | sed 's/^/      /' || echo "      (ninguno)"
  for prohibido in com.apple.security.cs.disable-library-validation com.apple.security.cs.allow-jit \
                   com.apple.security.cs.allow-unsigned-executable-memory com.apple.security.app-sandbox; do
    if grep -q "$prohibido" <<<"$ent"; then fallo "$nombre declara $prohibido, que el plan no permite."; fi
  done
  if grep -q com.apple.security.get-task-allow <<<"$ent"; then
    aviso "$nombre (Release) permite depuración (get-task-allow); revisa CODE_SIGN_INJECT_BASE_ENTITLEMENTS en project.yml."
  fi
}

paso "Firma de la app y del auxiliar"
comprobar "$APP" "la app"
comprobar "$APP/$HELPER_REL" "tls-mcp"

paso "Permisos declarados"
permisos "$APP" "la app"
APP_ENT="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
for requerido in com.apple.security.automation.apple-events com.apple.security.personal-information.calendars; do
  grep -q "$requerido" <<<"$APP_ENT" || fallo "A la app le falta el permiso $requerido."
done
permisos "$APP/$HELPER_REL" "tls-mcp"

paso "Último DMG"
ULTIMO=""
for f in "$DIST"/The-Last-System-*.dmg; do
  [[ -e "$f" ]] || continue
  if [[ -z "$ULTIMO" || "$f" -nt "$ULTIMO" ]]; then ULTIMO="$f"; fi
done
[[ -n "$ULTIMO" ]] || fallo "No hay ningún DMG en $DIST. Ejecuta make dmg."
VERSION="$(basename "$ULTIMO" .dmg)"; VERSION="${VERSION#The-Last-System-}"
echo "    $ULTIMO (versión $VERSION)"
hdiutil verify -quiet "$ULTIMO" || fallo "hdiutil verify ha encontrado errores en $ULTIMO."
echo "    hdiutil verify: correcto."

SUMAS="SHA256SUMS-$VERSION.txt"
[[ -f "$DIST/$SUMAS" ]] || fallo "Falta $DIST/$SUMAS."
( cd "$DIST" && shasum -a 256 -c "$SUMAS" ) | sed 's/^/    /' || fallo "Las sumas SHA-256 no coinciden."

paso "Contenido del disco (montado en solo lectura)"
MONTAJE="$(mktemp -d "${TMPDIR:-/tmp}/tls-verificar.XXXXXX")"
desmontar() {
  hdiutil detach -quiet "$MONTAJE" 2>/dev/null || hdiutil detach -quiet -force "$MONTAJE" 2>/dev/null || true
  rmdir "$MONTAJE" 2>/dev/null || true
}
trap desmontar EXIT
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$MONTAJE" "$ULTIMO" \
  || fallo "No se ha podido montar $ULTIMO."
[[ -d "$MONTAJE/$NOMBRE_APP.app" ]] || fallo "El DMG no contiene «$NOMBRE_APP.app»."
[[ -L "$MONTAJE/Aplicaciones" && "$(readlink "$MONTAJE/Aplicaciones")" == "/Applications" ]] \
  || fallo "El DMG no tiene el acceso «Aplicaciones» → /Applications."
[[ -s "$MONTAJE/LEEME.txt" ]] || fallo "El DMG no tiene LEEME.txt."
codesign --verify --deep --strict "$MONTAJE/$NOMBRE_APP.app" || fallo "La app del DMG no verifica."
VERSION_DMG_APP="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MONTAJE/$NOMBRE_APP.app/Contents/Info.plist")"
[[ "$VERSION_DMG_APP" == "$VERSION" ]] || fallo "La app del DMG es la $VERSION_DMG_APP, no la $VERSION."
echo "    App, «Aplicaciones» y LEEME.txt presentes; firma correcta; versión $VERSION_DMG_APP."

paso "Sandbox de los asistentes"
"$RAIZ/scripts/verificar-sandbox.sh"

paso "Verificación terminada"
