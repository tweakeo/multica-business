#!/bin/bash
# Genera el DMG instalable de The Last System (PLAN §9, cabecera de F0).
# Sala limpia: escrito solo desde la especificación del plan, sin abrir el script del fork.
#
# Cadena: Release arm64 → firma comprobada (app y Contents/Helpers/tls-mcp) → staging con
# «Aplicaciones» y LEEME.txt → hdiutil UDZO (APFS) → hdiutil verify → firma dentro del disco → SHA256SUMS.
#
# Uso: scripts/build-dmg.sh [--sin-compilar | --solo-compilar]
#   --sin-compilar   usa la app Release que ya está en $DERIVED
#   --solo-compilar  compila Release y comprueba la firma, sin crear el DMG (make release)
# Variables: DERIVED (build/DerivedData), DIST (dist), TLS_EXIGIR_FIRMA=1 (falla si es ad hoc)
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

DERIVED="${DERIVED:-build/DerivedData}"
DIST="${DIST:-dist}"
PROYECTO="TheLastSystem.xcodeproj"
ESQUEMA="TheLastSystem"
NOMBRE_APP="The Last System"

paso()  { printf '\n==> %s\n' "$*"; }
aviso() { printf 'AVISO: %s\n' "$*" >&2; }
fallo() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

COMPILAR=1
CREAR_DMG=1
case "${1:-}" in
  --sin-compilar)  COMPILAR=0 ;;
  --solo-compilar) CREAR_DMG=0 ;;
  -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) fallo "Opción desconocida: $1 (usa --help)." ;;
esac

for herramienta in xcodebuild codesign hdiutil shasum ditto lipo dwarfdump; do
  command -v "$herramienta" >/dev/null || fallo "Falta «$herramienta». Instala Xcode y ejecuta make bootstrap."
done
[[ -d "$PROYECTO" ]] || fallo "No existe $PROYECTO. Ejecuta make gen."

# Versión visible desde Base.xcconfig; número de build desde git (0 si aún no hay commits).
VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION[[:space:]]*=[[:space:]]*([0-9A-Za-z.\-]+).*/\1/p' Config/Base.xcconfig | tail -n 1)"
[[ -n "$VERSION" ]] || fallo "No encuentro MARKETING_VERSION en Config/Base.xcconfig."
if ! BUILD="$(git rev-list --count HEAD 2>/dev/null)"; then BUILD=0; fi

# Firma: con equipo (Signing.local.xcconfig) Xcode puede preparar certificado y perfil.
EQUIPO=""
if [[ -f Config/Signing.local.xcconfig ]]; then
  EQUIPO="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' Config/Signing.local.xcconfig | tail -n 1)"
fi
FIRMA_ARGS=()
FIRMA_TXT="firma ad hoc"
if [[ -n "$EQUIPO" ]]; then
  FIRMA_ARGS=(-allowProvisioningUpdates)
  FIRMA_TXT="equipo $EQUIPO"
fi

APP="$DERIVED/Build/Products/Release/$NOMBRE_APP.app"
HELPER_REL="Contents/Helpers/tls-mcp"

if [[ "$COMPILAR" == 1 ]]; then
  # Siempre desde limpio: una compilación incremental puede dejar dentro de la app un tls-mcp antiguo.
  paso "Compilando Release arm64 desde limpio · versión $VERSION · build $BUILD · $FIRMA_TXT"
  mkdir -p build
  LOG="build/xcodebuild-release.log"
  if ! xcodebuild -project "$PROYECTO" -scheme "$ESQUEMA" -configuration Release \
        -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
        ${FIRMA_ARGS[@]+"${FIRMA_ARGS[@]}"} \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CURRENT_PROJECT_VERSION="$BUILD" \
        clean build >"$LOG" 2>&1; then
    grep -E 'error:|BUILD FAILED|[Ss]igning|[Pp]rovisioning' "$LOG" | tail -n 25 >&2 || true
    fallo "La compilación Release ha fallado. Registro completo: $LOG"
  fi
  echo "Compilación correcta (registro: $LOG)."
fi

[[ -d "$APP" ]] || fallo "No encuentro la app compilada en $APP. Ejecuta antes: make release"
[[ -x "$APP/$HELPER_REL" ]] || fallo "Falta el auxiliar tls-mcp dentro de la app ($HELPER_REL)."

# Comprueba la firma de la app y del auxiliar; devuelve la autoridad (vacía si es ad hoc).
autoridad() {
  { codesign -dv --verbose=2 "$1" 2>&1 || true; } | awk '/^Authority=/ { if (!hecho) { print substr($0, 11); hecho = 1 } }'
}
equipo_firmado() {
  { codesign -dv --verbose=2 "$1" 2>&1 || true; } | awk -F= '/^TeamIdentifier=/ { print $2 }'
}
comprobar_firma() {
  local app="$1"
  codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1 \
    || fallo "La firma de la app no verifica ($app). Revisa: codesign --verify --deep --strict --verbose=4 \"$app\""
  codesign --verify --strict --verbose=2 "$app/$HELPER_REL" >/dev/null 2>&1 \
    || fallo "La firma de tls-mcp no verifica ($app/$HELPER_REL)."
}

paso "Comprobando firma y arquitectura"
comprobar_firma "$APP"
for binario in "$APP/Contents/MacOS/$NOMBRE_APP" "$APP/$HELPER_REL"; do
  ARQ="$(lipo -archs "$binario" 2>/dev/null || true)"
  [[ "$ARQ" == "arm64" ]] || fallo "$(basename "$binario") es «$ARQ»; la v1 es solo arm64."
done
# El tls-mcp embebido debe ser el recién enlazado (mismo UUID de Mach-O).
UUID_SUELTO="$({ dwarfdump --uuid "$DERIVED/Build/Products/Release/tls-mcp" 2>/dev/null || true; } | awk '{print $2}')"
UUID_EMBEBIDO="$({ dwarfdump --uuid "$APP/$HELPER_REL" 2>/dev/null || true; } | awk '{print $2}')"
[[ -n "$UUID_EMBEBIDO" && "$UUID_SUELTO" == "$UUID_EMBEBIDO" ]] \
  || fallo "El tls-mcp de dentro de la app no es el recién compilado. Ejecuta make dmg (compila desde limpio)."
VERSION_APP="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION_APP" == "$VERSION" ]] \
  || fallo "La app compilada es la $VERSION_APP y Base.xcconfig dice $VERSION. Recompila sin --sin-compilar."

# Lo que la app necesita llevar dentro (F1): letras, plantillas, el ejemplo de Ribera y tls-mcp.
paso "Comprobando lo que lleva dentro la app"
RECURSOS="$APP/Contents/Resources"
N_LETRAS="$(find "$RECURSOS" -path '*TLSDesign*' -name '*.ttf' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$N_LETRAS" -ge 4 ]] || fallo "La app no lleva las letras (Space Grotesk, DM Sans, JetBrains Mono): $N_LETRAS ficheros .ttf."
N_PLANTILLAS="$(find "$RECURSOS" -path '*TLSCore*/Plantillas/*' -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$N_PLANTILLAS" -ge 40 ]] || fallo "La app no lleva las plantillas: $N_PLANTILLAS."
EJEMPLO="$RECURSOS/Recursos/Ejemplos/Asesoria-Ribera"
[[ -f "$EJEMPLO/.tls/config.yaml" && -f "$EJEMPLO/Empresa.md" ]] || fallo "La app no lleva el ejemplo de Asesoría Ribera ($EJEMPLO)."
N_EJEMPLO="$(find "$EJEMPLO" -type f | wc -l | tr -d ' ')"
echo "Letras: $N_LETRAS · plantillas: $N_PLANTILLAS · ejemplo: $N_EJEMPLO ficheros · $HELPER_REL: sí."

AUT_APP="$(autoridad "$APP")"
AUT_HELPER="$(autoridad "$APP/$HELPER_REL")"
if [[ -n "$EQUIPO" ]]; then
  [[ "$AUT_APP" == "Apple Development:"* ]] \
    || fallo "Hay equipo configurado ($EQUIPO) pero la app no está firmada con Apple Development (autoridad: ${AUT_APP:-ad hoc})."
  [[ "$AUT_HELPER" == "Apple Development:"* ]] \
    || fallo "tls-mcp no está firmado con Apple Development (autoridad: ${AUT_HELPER:-ad hoc})."
  [[ "$(equipo_firmado "$APP")" == "$EQUIPO" && "$(equipo_firmado "$APP/$HELPER_REL")" == "$EQUIPO" ]] \
    || fallo "La app o tls-mcp están firmados con otro equipo distinto de $EQUIPO."
  echo "Firma correcta: $AUT_APP (app y tls-mcp)."
else
  [[ "${TLS_EXIGIR_FIRMA:-0}" == 1 ]] && fallo "Firma ad hoc y TLS_EXIGIR_FIRMA=1. Ejecuta make firma."
  aviso "firma ad hoc (sin equipo). Funciona, pero macOS pedirá permisos de nuevo tras cada actualización. Ejecuta make firma."
fi

[[ "$CREAR_DMG" == 1 ]] || exit 0

# Texto para quien instala: sin jerga técnica.
escribir_leeme() {
  cat <<EOF
The Last System $VERSION (build $BUILD)

CÓMO INSTALARLA
1. Arrastra «The Last System» a la carpeta «Aplicaciones» que ves en esta misma ventana.
2. Expulsa este disco (botón de expulsar junto a su nombre en Finder).
3. Abre The Last System desde Aplicaciones o desde Launchpad.

Para actualizar a una versión nueva, repite los mismos pasos y elige «Reemplazar».
Tus empresas y tus ajustes se conservan.

LA PRIMERA VEZ
Se abre la puesta en marcha: con tu carpeta (trabajas sobre una copia), desde cero
o con «Ver un ejemplo». Nada se escribe hasta que pulsas «Aplicar» y puedes dejarla
para más tarde. El manual está en el menú Ayuda.

LOS ASISTENTES
Cada área tiene un asistente (Mika en Dirección, el Comercial, el Contable…) que prepara
tareas, borradores y preguntas. Trabajan con tu Claude Code: instálalo, abre Terminal,
escribe claude e inicia sesión. Sin él, la app funciona igual y te lo explica en Asistentes.
Nada sale de la empresa sin tu OK: lo que se enviaría te espera en Decisiones.
Un interruptor en la barra de la ventana los para a todos. En el ejemplo todo es simulado.

SI MACOS NO LA DEJA ABRIR LA PRIMERA VEZ
Abre Ajustes del Sistema › Privacidad y seguridad, baja hasta el aviso sobre
«The Last System» y pulsa «Abrir igualmente». Solo hace falta una vez.

DÓNDE GUARDA TUS DATOS
- Las copias de tus empresas están en tu carpeta de inicio,
  dentro de «The Last System › Empresas» (~/The Last System/Empresas).
  Puedes abrirlas también con Finder u Obsidian.
- Sus ajustes y el buscador están en
  ~/Library/Application Support/The Last System
  (en Finder: menú Ir › Ir a la carpeta… y pega esa ruta).
En las copias y en el ejemplo, la app escribe y todo se puede deshacer (⌘Z);
lo que retiras va a la carpeta «Archivo», nunca se borra.
En tu carpeta real de The Last solo lee: no cambia nada.

REQUISITOS
Un Mac con chip de Apple (M1 o posterior) y macOS 15 Sequoia o posterior.
EOF
}

paso "Preparando el contenido del disco"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tls-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$NOMBRE_APP.app"
ln -s /Applications "$STAGE/Aplicaciones"
escribir_leeme >"$STAGE/LEEME.txt"
comprobar_firma "$STAGE/$NOMBRE_APP.app"

mkdir -p "$DIST"
DMG="$DIST/The-Last-System-$VERSION.dmg"
SUMAS="$DIST/SHA256SUMS-$VERSION.txt"
rm -f "$DMG" "$SUMAS"

paso "Creando $DMG"
CREADO=0
for intento in 1 2 3; do
  # hdiutil a veces devuelve «Resource busy» de forma transitoria: se reintenta.
  # APFS y no HFS+: HFS+ guarda los nombres descompuestos (NFD) y la firma sella «Área.md» o «1 · Dirección» compuestos
  # (NFC); con HFS+ la app del disco, y la que se copia a Aplicaciones, deja de verificar («sealed resource is missing»).
  if hdiutil create -volname "$NOMBRE_APP $VERSION" -srcfolder "$STAGE" -fs APFS -format UDZO -ov "$DMG" >/dev/null; then
    CREADO=1; break
  fi
  aviso "hdiutil create falló (intento $intento de 3); reintento en 3 s."
  sleep 3
done
[[ "$CREADO" == 1 ]] || fallo "hdiutil no ha podido crear el DMG."

paso "Verificando el DMG"
hdiutil verify -quiet "$DMG" || fallo "hdiutil verify ha encontrado errores en $DMG."
# La firma tiene que seguir valiendo dentro del disco (lo que Manu arrastra a Aplicaciones).
MONTAJE="$(mktemp -d "${TMPDIR:-/tmp}/tls-dmg-montaje.XXXXXX")"
hdiutil attach -quiet -readonly -nobrowse -noautoopen -mountpoint "$MONTAJE" "$DMG" || fallo "No he podido montar $DMG."
if ! codesign --verify --deep --strict "$MONTAJE/$NOMBRE_APP.app" 2>/dev/null; then
  hdiutil detach -quiet "$MONTAJE" || true; rmdir "$MONTAJE" 2>/dev/null || true
  fallo "La app de dentro del DMG no verifica su firma."
fi
hdiutil detach -quiet "$MONTAJE" || hdiutil detach -quiet -force "$MONTAJE" || true
rmdir "$MONTAJE" 2>/dev/null || true
echo "Firma correcta también dentro del disco."

( cd "$DIST" && shasum -a 256 "$(basename "$DMG")" >"$(basename "$SUMAS")" && shasum -a 256 -c "$(basename "$SUMAS")" >/dev/null ) \
  || fallo "No se ha podido escribir o comprobar $SUMAS."

TAMANO="$(du -h "$DMG" | awk '{print $1}')"
paso "DMG listo"
echo "  Disco:   $DMG ($TAMANO)"
echo "  Sumas:   $SUMAS"
echo "  SHA-256: $(awk '{print $1}' "$SUMAS")"
echo "  Firma:   ${AUT_APP:-ad hoc (sin equipo)}"
