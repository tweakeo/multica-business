#!/usr/bin/env bash
# Scans what a branch adds for secrets and personal data.
#
#   scripts/privacidad/escanear.sh                 # commits since origin/main + staged changes
#   scripts/privacidad/escanear.sh --base <ref>    # another base
#   scripts/privacidad/escanear.sh --staged        # staged changes only (before each commit)
#
# Only ADDED lines are checked, in two layers:
#   1. gitleaks (when installed): keys, tokens and credentials.
#   2. Own patterns: Spanish NIF/DNI/NIE/CIF, IBAN, phone numbers, real e-mail addresses, macOS
#      home paths, health terms, and a local deny list (.privacidad.local, never committed).
# A line can be accepted on purpose with the marker `privacidad:permitir`.
# Exits 1 when anything is found.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
DIR=scripts/privacidad
BASE=origin/main
SOLO_STAGED=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --staged) SOLO_STAGED=1; shift ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; exit 2 ;;
  esac
done

fallos=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- 1. gitleaks --------------------------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  if [ "$SOLO_STAGED" = 1 ]; then
    gitleaks git --staged --no-banner --redact -v . >"$tmp/gitleaks.txt" 2>&1 || fallos=1
  else
    BASE_SHA=$(git merge-base "$BASE" HEAD)
    gitleaks git --log-opts="$BASE_SHA..HEAD" --no-banner --redact -v . >"$tmp/gitleaks.txt" 2>&1 || fallos=1
    gitleaks git --staged --no-banner --redact -v . >>"$tmp/gitleaks.txt" 2>&1 || fallos=1
  fi
  if [ "$fallos" = 1 ]; then echo "✗ gitleaks encontró posibles secretos:"; cat "$tmp/gitleaks.txt"; else echo "✓ gitleaks: sin secretos"; fi
else
  echo "· gitleaks no está instalado (brew install gitleaks): se salta la capa 1"
fi

# --- 2. Own patterns over added lines -----------------------------------------
{
  if [ "$SOLO_STAGED" = 0 ]; then
    for c in $(git rev-list --reverse "$(git merge-base "$BASE" HEAD)"..HEAD); do
      git show --format= --unified=0 --no-color --diff-filter=AM "$c"
    done
  fi
  git diff --cached --unified=0 --no-color --diff-filter=AM
} | awk '
  /^\+\+\+ / { file = substr($0, 7); next }
  /^\+/ && !/^\+\+\+/ { print file "\t" substr($0, 2) }
' >"$tmp/anadido.tsv"

python3 -I "$DIR/patrones.py" "$DIR/permitidos.txt" .privacidad.local <"$tmp/anadido.tsv" >"$tmp/hallazgos.txt"

lineas=$(wc -l <"$tmp/anadido.tsv" | tr -d ' ')
if [ -s "$tmp/hallazgos.txt" ]; then
  fallos=1
  echo "✗ Datos que parecen personales en las líneas añadidas ($lineas revisadas):"
  sort -u "$tmp/hallazgos.txt" | awk -F'\t' '{printf "  %-26s %s  →  %s\n", $1, $2, $3}'
  echo "  Si es un dato inventado, añádelo a $DIR/permitidos.txt o marca la línea con privacidad:permitir."
else
  echo "✓ Patrones propios: nada en $lineas líneas añadidas"
fi
exit "$fallos"
