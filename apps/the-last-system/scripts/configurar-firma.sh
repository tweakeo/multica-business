#!/bin/bash
# Configura la firma con tu equipo de Apple (PLAN §3.1 y §8: firma estable desde F0).
# Escribe Config/Signing.local.xcconfig, que no se versiona y que Base.xcconfig incluye.
#
# Uso:
#   scripts/configurar-firma.sh               busca un certificado «Apple Development» y lo configura
#   scripts/configurar-firma.sh --equipo ID   fuerza el Team ID (Xcode creará el certificado al compilar)
#   scripts/configurar-firma.sh --ad-hoc      vuelve a la firma local (borra Signing.local.xcconfig)
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINO="$RAIZ/Config/Signing.local.xcconfig"

EQUIPO_FORZADO=""
case "${1:-}" in
  --equipo)
    EQUIPO_FORZADO="${2:-}"
    [[ "$EQUIPO_FORZADO" =~ ^[A-Z0-9]{10}$ ]] || { echo "El Team ID son 10 letras mayúsculas o números (por ejemplo AB12CD34EF)." >&2; exit 2; }
    ;;
  --ad-hoc)
    rm -f "$DESTINO"
    echo "Firma local (ad hoc) restaurada: se ha quitado Config/Signing.local.xcconfig."
    exit 0
    ;;
  -h|--help)
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  "") ;;
  *) echo "Opción desconocida: $1 (usa --help)." >&2; exit 2 ;;
esac

# Escribe el xcconfig local con firma automática del equipo indicado.
escribir() {
  local equipo="$1" origen="$2"
  cat >"$DESTINO" <<EOF
// Generado por scripts/configurar-firma.sh el $(date '+%Y-%m-%d %H:%M'). No se versiona.
// Origen del equipo: $origen
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = $equipo
EOF
  echo "Listo: Config/Signing.local.xcconfig firma con el equipo $equipo."
  echo "Las compilaciones con equipo usan -allowProvisioningUpdates para que Xcode prepare el certificado."
}

if [[ -n "$EQUIPO_FORZADO" ]]; then
  escribir "$EQUIPO_FORZADO" "indicado a mano (--equipo)"
  exit 0
fi

# Identidades válidas «Apple Development: …» del llavero de inicio de sesión.
IDENTIDADES="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development: ' || true)"

if [[ -z "$IDENTIDADES" ]]; then
  cat <<'EOF'
No hay ningún certificado «Apple Development» en este Mac. Se mantiene la firma local (ad hoc):
la app compila y funciona, pero macOS volverá a pedir permisos tras cada actualización.

Para crear el certificado (gratis, con tu Apple ID):
  1. Abre Xcode › Ajustes… › Cuentas.
  2. Si no aparece tu Apple ID, pulsa «+» › Apple ID e inicia sesión.
  3. Selecciona tu equipo («Personal Team») y pulsa «Manage Certificates…».
  4. Pulsa «+» › «Apple Development» y cierra la ventana.
  5. Vuelve a ejecutar: make firma
EOF
  # Pista: equipos que Xcode ya conoce (solo el identificador, nada más).
  EQUIPOS_XCODE="$(defaults read com.apple.dt.Xcode 2>/dev/null | grep -oE 'teamID = "?[A-Z0-9]{10}' | grep -oE '[A-Z0-9]{10}$' | sort -u || true)"
  if [[ -n "$EQUIPOS_XCODE" ]]; then
    echo
    echo "Xcode conoce estos equipos: $(echo "$EQUIPOS_XCODE" | tr '\n' ' ')"
    echo "También puedes ejecutar: scripts/configurar-firma.sh --equipo <ID> (Xcode creará el certificado al compilar)."
  fi
  if [[ -f "$DESTINO" ]]; then
    echo
    echo "Ojo: ya existe Config/Signing.local.xcconfig de antes y se ha dejado como estaba."
    echo "Para volver a ad hoc del todo: scripts/configurar-firma.sh --ad-hoc"
  fi
  exit 0
fi

# Primera identidad: hash SHA-1 y nombre.
LINEA="$(printf '%s\n' "$IDENTIDADES" | head -n 1)"
HASH="$(printf '%s\n' "$LINEA" | awk '{print $2}')"
NOMBRE="$(printf '%s\n' "$LINEA" | sed -E 's/^[^"]*"(.*)"[^"]*$/\1/')"
CUANTAS="$(printf '%s\n' "$IDENTIDADES" | wc -l | tr -d ' ')"

# El Team ID es el OU del sujeto del certificado (no el código entre paréntesis del nombre).
PEM="$(security find-certificate -a -c "$NOMBRE" -Z -p 2>/dev/null | awk -v h="$HASH" '
  /^SHA-1 hash:/ { coge = ($3 == h) }
  coge && /BEGIN CERTIFICATE/ { dentro = 1 }
  coge && dentro { print }
  /END CERTIFICATE/ { dentro = 0 }
')"
SUJETO="$(printf '%s\n' "$PEM" | /usr/bin/openssl x509 -noout -subject 2>/dev/null || true)"
EQUIPO="$(printf '%s\n' "$SUJETO" | grep -oE 'OU ?= ?[A-Z0-9]{10}' | grep -oE '[A-Z0-9]{10}$' | head -n 1 || true)"

if [[ -z "$EQUIPO" ]]; then
  echo "He encontrado el certificado «$NOMBRE», pero no consigo leer su Team ID." >&2
  echo "Búscalo en Xcode › Ajustes › Cuentas (columna Team) y ejecuta: scripts/configurar-firma.sh --equipo <ID>" >&2
  exit 1
fi

if [[ "$CUANTAS" -gt 1 ]]; then
  echo "Hay $CUANTAS certificados «Apple Development»; uso el primero. Para otro equipo: --equipo <ID>."
fi
escribir "$EQUIPO" "certificado Apple Development del llavero"

# Comprobación rápida de que Xcode lo recoge (no es fatal).
if [[ -d "$RAIZ/TheLastSystem.xcodeproj" ]]; then
  AJUSTES="$(xcodebuild -project "$RAIZ/TheLastSystem.xcodeproj" -scheme TheLastSystem -configuration Release \
       -showBuildSettings 2>/dev/null || true)"
  if grep -q "DEVELOPMENT_TEAM = $EQUIPO" <<<"$AJUSTES"; then
    echo "Xcode ve el equipo $EQUIPO en la configuración Release."
  else
    echo "AVISO: Xcode no muestra todavía DEVELOPMENT_TEAM = $EQUIPO. Ejecuta make gen y vuelve a probar." >&2
  fi
fi
