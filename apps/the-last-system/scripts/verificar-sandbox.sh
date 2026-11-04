#!/bin/bash
# Prueba del sandbox de los asistentes (PLAN §5.3, §8, §9 F1 criterio 8 y §10). La lanza make verify.
# Repetir tras cada actualización de macOS y de Claude Code.
#
# 1. Pruebas de TLSAgents con Claude Code de verdad (TLS_SONDA_REAL=1): perfil, preflight de flags,
#    sesión dentro del perfil, lista blanca medida con un init real, InitGuard ante un segundo servidor MCP
#    y reanudación con el mismo session_id. Gasto mínimo: dos respuestas de una palabra con haiku.
# 2. Con el perfil agente.sb que deja TLSAgents, desde la shell y sin Swift:
#    secreto de la empresa → EPERM · ~/Documents → EPERM · fichero personal fuera del agente → EPERM ·
#    socket ajeno → EPERM (el del MCP y el de DNS, sí) · osascript (también JXA) → EPERM · auth status → loggedIn:true.
#
# Variables: DERIVED (build/DerivedData), SPM_SCRATCH (build/spm), TLS_SONDA_ESTADO (build/sonda-agentes) y
# TLS_SONDA_PAQUETE (Packages/TLSKit; otro paquete con TLSAgents para probarlo aislado).
# Nunca toca ~/.claude/settings.json ni usa bypassPermissions.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

DERIVED="${DERIVED:-build/DerivedData}"
SPM_SCRATCH="${SPM_SCRATCH:-build/spm}"
ESTADO="${TLS_SONDA_ESTADO:-$RAIZ/build/sonda-agentes}"
PAQUETE="${TLS_SONDA_PAQUETE:-Packages/TLSKit}"
LOG="$RAIZ/build/verificar-sandbox.log"

paso()  { printf '    · %s\n' "$*"; }
bien()  { printf '      correcto: %s\n' "$*"; }
fallo() { printf '\nERROR (sandbox): %s\n' "$*" >&2; exit 1; }

# tls-mcp de la app (Release si existe; si no, Debug).
MCP=""
for conf in Release Debug; do
  c="$DERIVED/Build/Products/$conf/The Last System.app/Contents/Helpers/tls-mcp"
  [[ "$c" == /* ]] || c="$RAIZ/$c"
  if [[ -x "$c" ]]; then MCP="$c"; break; fi
done
[[ -n "$MCP" ]] || fallo "No encuentro tls-mcp en $DERIVED. Ejecuta antes: make build"

# Carpeta de empresa de prueba en /tmp, con un secreto sintético en la carpeta privada.
VAULT="$(mktemp -d /private/tmp/tls-sonda-vault.XXXXXX)"
SECRETO="$VAULT/4 · Finanzas/privado/secreto.md"
mkdir -p "$(dirname "$SECRETO")"
echo "secreto de prueba (sintético)" > "$SECRETO"
OTRO_SOCKET="/private/tmp/tls-sonda-otro.$$.sock"
OYENTES=()
limpiar() {
  for p in "${OYENTES[@]:-}"; do [[ -n "$p" ]] && { kill "$p"; wait "$p"; } 2>/dev/null || true; done
  rm -rf "$VAULT"; rm -f "$OTRO_SOCKET" "${SOCKET:-/nonexistent}" 2>/dev/null || true
}
trap limpiar EXIT

paso "Pruebas de TLSAgents con Claude Code (registro: ${LOG#$RAIZ/})"
mkdir -p "$(dirname "$LOG")"
set +e
TLS_SONDA_REAL=1 TLS_SONDA_MCP="$MCP" TLS_SONDA_ESTADO="$ESTADO" TLS_SONDA_VAULT="$VAULT" \
  swift test --package-path "$PAQUETE" --scratch-path "$SPM_SCRATCH" --filter TLSAgentsTests >"$LOG" 2>&1
ESTADO_TEST=$?
set -e
grep -E '^(AVISO|Claude Code|Sesión|Lista blanca|Guardia|Reanudación)' "$LOG" | sed 's/^/      /' || true
grep -E '✘|error:' "$LOG" | head -20 | sed 's/^/      /' || true
[[ $ESTADO_TEST -eq 0 ]] || fallo "Las pruebas de TLSAgents han fallado (mira $LOG)."
grep -q 'Test perfilParaElGuion() passed' "$LOG" || fallo "La prueba real no ha corrido (¿falta TLS_SONDA_REAL?)."
bien "$(grep -E 'Test run with [0-9]+ tests' "$LOG" | tail -1 | sed 's/^[^T]*//')"

ENV_FILE="$ESTADO/ejecuciones/verificacion/verificacion.env"
[[ -f "$ENV_FILE" ]] || fallo "TLSAgents no ha dejado el perfil de verificación ($ENV_FILE)."
# shellcheck disable=SC1090
source "$ENV_FILE"   # PERFIL, CLAUDE, SOCKET, AGENTE, EJECUCION, TMPDIR_AGENTE (generado por las pruebas)
[[ -f "$PERFIL" && -x "$CLAUDE" ]] || fallo "Falta el perfil o el binario de Claude."

ENTORNO=(env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" LANG=es_ES.UTF-8 PATH=/usr/bin:/bin:/usr/sbin:/sbin
         TMPDIR="$TMPDIR_AGENTE" DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1)
SB=(/usr/bin/sandbox-exec -f "$PERFIL")

# Exige que la orden falle con «Operation not permitted» y sin sacar nada por stdout.
exigir_eperm() {
  local que="$1"; shift
  local out err
  out="$("${ENTORNO[@]}" "${SB[@]}" "$@" 2>/dev/null)" || true
  err="$("${ENTORNO[@]}" "${SB[@]}" "$@" 2>&1 >/dev/null)" || true
  [[ -z "$out" ]] || fallo "$que: el asistente ha podido leer algo."
  grep -q 'Operation not permitted' <<<"$err" || fallo "$que: se esperaba EPERM y ha dado: ${err:-nada}"
  bien "$que → EPERM"
}

paso "Comprobaciones desde la shell con el perfil generado (${PERFIL#$RAIZ/})"
grep -q 'secreto de prueba' "$SECRETO" || fallo "El secreto de prueba no se puede leer ni sin sandbox."
exigir_eperm "cat del secreto de la empresa" /bin/cat "$SECRETO"
# La carpeta se abre como fichero: sin sandbox da «Is a directory», así nunca se lista su contenido.
if [[ -d "$HOME/Documents" ]]; then exigir_eperm "~/Documents" /bin/cat "$HOME/Documents"; fi
FUERA="$ESTADO/fuera/secreto.md"
mkdir -p "$(dirname "$FUERA")"; echo "fuera del agente" > "$FUERA"
exigir_eperm "fichero personal fuera del agente" /bin/cat "$FUERA"
exigir_eperm "osascript" /usr/bin/osascript -e 'return 1'
# F5 · mail: tampoco JXA (lo que usa la app para leer Mail). El guion es «1»: no habla con Mail aunque fallara la caja.
exigir_eperm "osascript JXA" /usr/bin/osascript -l JavaScript -e '1'

# Sockets: el del MCP de la carpeta sí; uno ajeno no; el de DNS sí (sin él no hay red).
escuchar() {
  /usr/bin/perl -e 'use Socket; unlink $ARGV[0]; socket(my $s, AF_UNIX, SOCK_STREAM, 0) or die;
    bind($s, pack_sockaddr_un($ARGV[0])) or die "bind: $!"; listen($s, 16) or die; sleep 60' "$1" &
  OYENTES+=($!)
  for _ in $(seq 1 50); do [[ -S "$1" ]] && return 0; sleep 0.1; done
  fallo "No se ha podido crear el socket de prueba $1."
}
CONECTAR='use Socket; socket(my $s, AF_UNIX, SOCK_STREAM, 0) or die;
  if (connect($s, pack_sockaddr_un($ARGV[0]))) { print "conectado\n" } else { printf "error %d\n", $!+0 }'
mkdir -p "$(dirname "$SOCKET")"
escuchar "$SOCKET"; escuchar "$OTRO_SOCKET"
[[ "$(/usr/bin/perl -e "$CONECTAR" "$OTRO_SOCKET")" == conectado ]] || fallo "El socket ajeno no acepta ni sin sandbox."
r="$("${ENTORNO[@]}" "${SB[@]}" /usr/bin/perl -e "$CONECTAR" "$OTRO_SOCKET")"
[[ "$r" == "error 1" ]] || fallo "Socket ajeno: se esperaba EPERM y ha dado: $r"
bien "socket ajeno → EPERM"
r="$("${ENTORNO[@]}" "${SB[@]}" /usr/bin/perl -e "$CONECTAR" "$SOCKET")"
[[ "$r" == conectado ]] || fallo "El socket del MCP de la carpeta no se puede usar: $r"
bien "socket del MCP de la carpeta → se conecta"
r="$("${ENTORNO[@]}" "${SB[@]}" /usr/bin/perl -e "$CONECTAR" /private/var/run/mDNSResponder)"
[[ "$r" == conectado ]] || fallo "Sin DNS dentro del perfil (no habría red): $r"
bien "DNS (mDNSResponder) → se conecta"

# La sesión de Claude sigue viva dentro del perfil final (no se imprime nada más que loggedIn).
AUTH="$(cd "$AGENTE" && "${ENTORNO[@]}" "${SB[@]}" "$CLAUDE" auth status --json 2>/dev/null || true)"
LOGGED="$(plutil -extract loggedIn raw -o - - <<<"$AUTH" 2>/dev/null || echo "ilegible")"
[[ "$LOGGED" == true ]] || fallo "Dentro del perfil, claude auth status no da loggedIn:true (da: $LOGGED). Abre Claude Code e inicia sesión."
bien "claude auth status dentro del perfil → loggedIn:true ($("${ENTORNO[@]}" "$CLAUDE" --version 2>/dev/null | head -n 1))"

echo "    Sandbox de los asistentes: correcto."
