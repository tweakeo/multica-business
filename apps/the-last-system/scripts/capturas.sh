#!/bin/bash
# make capturas: PNG fuera de pantalla de las pantallas principales de F1 a F6 con Asesoría Ribera y la fixture
# G3 (en claro y en oscuro) y cuatro índices HTML (index.html, f3.html, f4.html y f5.html). No abre la app ni toca el ratón: pinta las vistas en ventanas que nunca se enseñan
# (Tests/TLSUITests/Integracion/CapturasF1Tests.swift y CapturasF2Tests.swift). Ribera se copia a una carpeta
# temporal y se borra al acabar. Las dos tandas van una detrás de otra (comparten la apariencia forzada).
# Variables: CAPTURAS (build/capturas), SPM_SCRATCH (build/spm)
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

CAPTURAS="${CAPTURAS:-build/capturas}"
SPM_SCRATCH="${SPM_SCRATCH:-build/spm}"
mkdir -p "$CAPTURAS"
DESTINO="$(cd "$CAPTURAS" && pwd)"

# Las de la vez anterior (solo las de este objetivo; las carpetas de cada rol se quedan).
rm -f "$DESTINO"/[0-9][0-9]-*.png "$DESTINO/index.html"

echo "==> Pintando las pantallas de F1 en $DESTINO"
TLS_CAPTURAS="$DESTINO" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter CapturasF1Tests
echo "==> Pintando las pantallas de F2 en $DESTINO"
TLS_CAPTURAS="$DESTINO" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter CapturasF2Tests

n=$(find "$DESTINO" -maxdepth 1 -name '[0-9][0-9]-*.png' | wc -l | tr -d ' ')
[[ -f "$DESTINO/index.html" && "$n" -ge 70 ]] || { echo "ERROR: faltan capturas ($n PNG)" >&2; exit 1; }
echo "==> $n capturas de F1 y F2. Índice: $DESTINO/index.html"

# F3: la puesta en marcha (bienvenida y cada paso), ordenar (inventario, preparación, vista previa, comprobación),
# actualizar la copia, Multica, el tutorial con su velo, el manual, el arranque y la línea de Hoy. Cada tanda deja sus
# PNG en su carpeta (f3-pasos, f3-ordenar, f3-tutorial, f3-integracion).
rm -rf "$DESTINO/f3-pasos" "$DESTINO/f3-ordenar" "$DESTINO/f3-tutorial" "$DESTINO/f3-integracion" "$DESTINO/f3.html"
echo "==> Pintando la puesta en marcha, ordenar, el tutorial y el manual (F3) en $DESTINO/f3-*"
TLS_CAPTURAS="$DESTINO" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter 'CapturasPasosTests|CapturasPasoOrdenarTests|CapturasOrdenarTests|CapturasTutorialTests|IntegracionPuestaTests/capturas'

# Índice de F3: una sección por tanda, en claro y oscuro uno al lado del otro.
{
  echo '<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Capturas de F3</title>'
  echo '<style>body{font-family:-apple-system,sans-serif;margin:24px;background:#f4f4f6;color:#111}'
  echo 'h1{font-size:22px}h2{font-size:17px;margin-top:32px}figure{display:inline-block;margin:8px;vertical-align:top}'
  echo 'img{max-width:460px;border:1px solid #ccc;border-radius:8px}figcaption{font-size:12px;color:#555}'
  echo '@media (prefers-color-scheme: dark){body{background:#000;color:#eee}img{border-color:#333}figcaption{color:#aaa}}</style>'
  echo '</head><body><h1>F3 · Puesta en marcha</h1><p><a href="index.html">F1 y F2</a></p>'
  for d in f3-integracion f3-pasos f3-ordenar f3-tutorial; do
    [[ -d "$DESTINO/$d" ]] || continue
    echo "<h2>$d</h2>"
    for f in "$DESTINO/$d"/*.png; do
      [[ -f "$f" ]] || continue
      nombre="$(basename "$f")"
      echo "<figure><img src=\"$d/$nombre\" loading=\"lazy\"><figcaption>${nombre%.png}</figcaption></figure>"
    done
  done
  echo '</body></html>'
} > "$DESTINO/f3.html"

m=$(find "$DESTINO"/f3-* -name '*.png' | wc -l | tr -d ' ')
[[ "$m" -ge 100 ]] || { echo "ERROR: faltan capturas de F3 ($m PNG)" >&2; exit 1; }
echo "==> $m capturas de F3. Índice: $DESTINO/f3.html"

# F4: los asistentes (Asistentes, la ficha de un asistente con sus permisos, rutinas y trabajos, la tarea con su asistente
# trabajando, Equipo con la Bitácora, la barra lateral y el aviso sin Claude Code) y Mika (⌘J, Decisiones con la
# aprobación sensible e invalidada, la pregunta y la propuesta de mejora, Hoy con la línea de Mika y la barra de menús).
rm -rf "$DESTINO/f4-asistentes" "$DESTINO/f4-mika" "$DESTINO/f4.html"
mkdir -p "$DESTINO/f4-asistentes" "$DESTINO/f4-mika"
echo "==> Pintando los asistentes (F4) en $DESTINO/f4-asistentes"
TLS_CAPTURAS="$DESTINO/f4-asistentes" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter 'CapturasAsistentesTests|CapturasIntegracionTests'
echo "==> Pintando Mika, Decisiones, Hoy y la barra de menús (F4) en $DESTINO/f4-mika"
TLS_CAPTURAS="$DESTINO/f4-mika" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter 'CapturasMikaTests'

{
  echo '<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Capturas de F4</title>'
  echo '<style>body{font-family:-apple-system,sans-serif;margin:24px;background:#f4f4f6;color:#111}'
  echo 'h1{font-size:22px}h2{font-size:17px;margin-top:32px}figure{display:inline-block;margin:8px;vertical-align:top}'
  echo 'img{max-width:460px;border:1px solid #ccc;border-radius:8px}figcaption{font-size:12px;color:#555}'
  echo '@media (prefers-color-scheme: dark){body{background:#000;color:#eee}img{border-color:#333}figcaption{color:#aaa}}</style>'
  echo '</head><body><h1>F4 · Asistentes</h1><p><a href="index.html">F1 y F2</a> · <a href="f3.html">F3</a></p>'
  for d in f4-asistentes f4-mika; do
    [[ -d "$DESTINO/$d" ]] || continue
    echo "<h2>$d</h2>"
    for f in "$DESTINO/$d"/*.png; do
      [[ -f "$f" ]] || continue
      nombre="$(basename "$f")"
      echo "<figure><img src=\"$d/$nombre\" loading=\"lazy\"><figcaption>${nombre%.png}</figcaption></figure>"
    done
  done
  echo '</body></html>'
} > "$DESTINO/f4.html"

k=$(find "$DESTINO"/f4-* -name '*.png' | wc -l | tr -d ' ')
[[ "$k" -ge 40 ]] || { echo "ERROR: faltan capturas de F4 ($k PNG)" >&2; exit 1; }
echo "==> $k capturas de F4. Índice: $DESTINO/f4.html"

# F5 y F6: Conexiones (Mail antes del permiso, denegado, cuentas, Calendario, añadir un programa, revisar herramientas y
# la matriz de Avanzado), el Buzón, las tarjetas nuevas de Decisiones, «Pasar a mi carpeta real» (carpetas sintéticas) y
# lo que monta la integración con el adaptador de verdad sobre dobles (el ejemplo, una copia conectada, Hoy, Decisiones
# y Ajustes). Nada toca Mail, Calendario, la red ni el Llavero.
rm -rf "$DESTINO/f5-conexiones" "$DESTINO/f5-buzon-relevo" "$DESTINO/f5-integracion" "$DESTINO/f5.html"
mkdir -p "$DESTINO/f5-conexiones" "$DESTINO/f5-buzon-relevo" "$DESTINO/f5-integracion"
echo "==> Pintando Conexiones (F5) en $DESTINO/f5-conexiones"
TLS_CAPTURAS="$DESTINO/f5-conexiones" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter 'CapturasConexionesTests'
echo "==> Pintando el Buzón, las tarjetas y el relevo (F5 y F6) en $DESTINO/f5-buzon-relevo"
TLS_CAPTURAS="$DESTINO/f5-buzon-relevo" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter 'CapturasBuzonRelevoTests'
echo "==> Pintando la integración de F5 en $DESTINO/f5-integracion"
TLS_CAPTURAS="$DESTINO/f5-integracion" swift test --package-path Packages/TLSKit --scratch-path "$SPM_SCRATCH" \
  --filter 'CapturasF5IntegracionTests'

{
  echo '<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Capturas de F5 y F6</title>'
  echo '<style>body{font-family:-apple-system,sans-serif;margin:24px;background:#f4f4f6;color:#111}'
  echo 'h1{font-size:22px}h2{font-size:17px;margin-top:32px}figure{display:inline-block;margin:8px;vertical-align:top}'
  echo 'img{max-width:460px;border:1px solid #ccc;border-radius:8px}figcaption{font-size:12px;color:#555}'
  echo '@media (prefers-color-scheme: dark){body{background:#000;color:#eee}img{border-color:#333}figcaption{color:#aaa}}</style>'
  echo '</head><body><h1>F5 · Conexiones y F6 · Relevo</h1><p><a href="index.html">F1 y F2</a> · <a href="f3.html">F3</a> · <a href="f4.html">F4</a></p>'
  for d in f5-integracion f5-conexiones f5-buzon-relevo; do
    [[ -d "$DESTINO/$d" ]] || continue
    echo "<h2>$d</h2>"
    for f in "$DESTINO/$d"/*.png; do
      [[ -f "$f" ]] || continue
      nombre="$(basename "$f")"
      echo "<figure><img src=\"$d/$nombre\" loading=\"lazy\"><figcaption>${nombre%.png}</figcaption></figure>"
    done
  done
  echo '</body></html>'
} > "$DESTINO/f5.html"

j=$(find "$DESTINO"/f5-* -name '*.png' | wc -l | tr -d ' ')
[[ "$j" -ge 40 ]] || { echo "ERROR: faltan capturas de F5 y F6 ($j PNG)" >&2; exit 1; }
echo "==> $j capturas de F5 y F6. Índice: $DESTINO/f5.html"
