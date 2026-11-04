#!/bin/bash
# Conformidad local (PLAN §10 y §9 F1).
#  1. swift test --filter ConformidadTests: casos golden de Tests/Conformidad/Casos (conversión G2, ida y vuelta
#     sin cambios, lectura y operaciones del escritor), validador del ejemplo y contrato de import_hash.
#     TLS_ACTUALIZAR_GOLDEN=1 regenera los esperado/ (revisa el diff antes de commitear).
#  2. Si la carpeta G2 de Ribera está en este Mac (TLS_RIBERA_G2, por defecto ~/TLS Empresas/DEV - Asesoría Ribera):
#     dos conversiones con tls-tool dan el mismo hash de árbol. Que el ejemplo versionado sea la conversión más su
#     capa hecha a mano (los asistentes y los retoques de F4, Tests/Conformidad/CapaRibera.swift) lo comprueba el paso 1.
#     Con --regenerar-ribera, vuelve a generar App/Recursos/Ejemplos/Asesoria-Ribera (conversión + capa).
#  3. Si TLS_CONFORMIDAD_G3 apunta a una COPIA de tu carpeta, dos inventarios seguidos son idénticos.
# Tus datos reales nunca entran en el repositorio: lo temporal va a build/ y se borra.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"
PKG="Packages/TLSKit"
SCRATCH="${SPM_SCRATCH:-build/spm-conformidad}"
EJEMPLO="App/Recursos/Ejemplos/Asesoria-Ribera"
RIBERA_G2="${TLS_RIBERA_G2:-$HOME/TLS Empresas/DEV - Asesoría Ribera}"
REGENERAR=0

for arg in "$@"; do
  case "$arg" in
    --regenerar-ribera) REGENERAR=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

paso()  { printf '\n==> %s\n' "$*"; }
fallo() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# Nunca iCloud Drive ni rutas privadas: ni para leer ni para escribir.
fuera_de_icloud() {
  case "$1" in
    *"/Library/Mobile Documents/"*|*"/vault-copia"*) fallo "$2 debe estar fuera de iCloud Drive: $1" ;;
  esac
}

mkdir -p "$RAIZ/build"
TMP="$(mktemp -d "$RAIZ/build/conformidad.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

paso "Compilando tls-tool"
swift build --package-path "$PKG" --scratch-path "$SCRATCH" --product tls-tool >/dev/null
TOOL="$(swift build --package-path "$PKG" --scratch-path "$SCRATCH" --show-bin-path)/tls-tool"

if [[ $REGENERAR -eq 1 ]]; then
  fuera_de_icloud "$RIBERA_G2" "TLS_RIBERA_G2"
  [[ -d "$RIBERA_G2" ]] || fallo "No encuentro la carpeta G2 de Ribera: $RIBERA_G2"
  paso "Regenerando $EJEMPLO desde $RIBERA_G2 (conversión + capa de Ribera)"
  # El ejemplo es la conversión más su capa (CapaRibera.swift): la prueba la aplica y conserva lo añadido a mano.
  TLS_ACTUALIZAR_GOLDEN=1 TLS_RIBERA_G2="$RIBERA_G2" swift test --package-path "$PKG" --scratch-path "$SCRATCH" \
    --filter "EjemploRibera/conversionIgualAlEjemplo"
fi

paso "Pruebas de conformidad del paquete"
swift test --package-path "$PKG" --scratch-path "$SCRATCH" --filter ConformidadTests

if [[ -d "$RIBERA_G2" ]]; then
  fuera_de_icloud "$RIBERA_G2" "TLS_RIBERA_G2"
  paso "Ribera: dos conversiones dan el mismo árbol (el ejemplo = conversión + capa lo comprobó el paso anterior)"
  hash_de() { "$TOOL" convertir-g2 "$RIBERA_G2" "$1" --clase demo --hoy 2026-10-19 | sed -n 's/^Hash del árbol: //p'; }
  H1="$(hash_de "$TMP/ribera-1")"
  H2="$(hash_de "$TMP/ribera-2")"
  [[ -n "$H1" && "$H1" == "$H2" ]] || fallo "Dos conversiones de Ribera dan árboles distintos ($H1 / $H2)."
  echo "Correcto: hash del árbol $H1 en las dos conversiones."
else
  echo
  echo "Sin la carpeta G2 de Ribera ($RIBERA_G2): solo se comprueba el ejemplo versionado."
fi

if [[ -z "${TLS_CONFORMIDAD_G3:-}" ]]; then
  echo
  echo "Sin TLS_CONFORMIDAD_G3: no se comprueba ninguna copia. Ejemplo:"
  echo "  TLS_CONFORMIDAD_G3=\"\$HOME/The Last System/Empresas/The Last (copia AAAA-MM-DD)\" make conformidad"
  exit 0
fi

COPIA="$TLS_CONFORMIDAD_G3"
fuera_de_icloud "$COPIA" "TLS_CONFORMIDAD_G3 (debe ser una copia en ~/The Last System/Empresas, no la carpeta real)"
[[ -d "$COPIA" ]] || fallo "TLS_CONFORMIDAD_G3 no es una carpeta: $COPIA"

paso "Ida y vuelta sobre la copia: dos inventarios seguidos"
"$TOOL" inventario "$COPIA" >"$TMP/1.txt"
"$TOOL" inventario "$COPIA" >"$TMP/2.txt"
if cmp -s "$TMP/1.txt" "$TMP/2.txt"; then
  echo "Correcto: $(wc -l <"$TMP/1.txt" | tr -d ' ') líneas de inventario idénticas en las dos pasadas."
else
  diff "$TMP/1.txt" "$TMP/2.txt" | head -n 20 >&2 || true
  fallo "El inventario de la copia ha cambiado entre dos pasadas."
fi
