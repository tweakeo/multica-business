# Metodología · Dossier + Propuesta económica (The Last System) — v4

> **v4** sustituye al modelo de 2 PDF / 4 docs. Por oportunidad se entregan **2 documentos**: **Dossier combinado** (Diagnóstico + Propuesta) + **Propuesta económica** aparte. Fuente maestra = **HTML editable en el navegador**. 

## Los 2 entregables
1. **DOSSIER** (1 PDF): **Parte 1 Diagnóstico** + **Parte 2 Propuesta de consultoría**. Portada → índice (con "página clave") → "PARTE 1" → diagnóstico → "PARTE 2" → propuesta.
2. **PROPUESTA ECONÓMICA** (doc aparte): oferta económica + contrato simplificado + siguientes pasos.

## Fuente maestra: HTML editable (Chrome)
- Barra: **Editar textos · Exportar a PDF · Descargar HTML editado · Restablecer**. Autoguardado en **localStorage**.
- Flujo: abrir en Chrome → editar → exportar PDF. **Las ediciones viven en localStorage y NO viajan**: para guardar/compartir una versión usar **"Descargar HTML editado"**.

## Plantillas genéricas (esta carpeta `Recursos/`)
- `Dossier (plantilla editable).html` · `Propuesta económica (plantilla).html` · `assets/` · `README - plantillas.txt`.
- Llevan el **ejemplo ficticio** con placeholders `[CLIENTE]` / `[CONTACTO]` / `[FECHA]`.

## Numeración por parte + páginas clave
- **Numeración POR PARTE (no continua), coloreada**: Parte 1 azul `#1a3a8a` · Parte 2 magenta `#c20069`.
- **Indicadores "Página clave"** en: Resumen ejecutivo · Matriz de madurez (Parte 1) · Resumen ejecutivo de la propuesta · Solución tras diagnóstico (Parte 2). El índice los marca igual.
- Aperturas "PARTE 1"/"PARTE 2" minimalistas.

## TONO (lo más importante — auditar siempre)
- **Estado:** "sin estructura interna: depende de los empleados, no de sus sistemas". NUNCA "vive de las personas".
- **Dolor:** breve, "sin proceso ni control", "a base de memoria". NUNCA "a mano", "a ciegas".
- **Solución:** mecanismo → beneficio → siguiente **área**. NUNCA "el resto avanza", "desde el orden", "siguiente foco".
- **Ventas** = "oportunidades" (no "entrantes"). **Operaciones** ≠ "desatascar el cuello".
- **Herramientas:** dolor = "información dispersa + falta de sistema de colaboración".
- Frases con verbo, no telegráficas. **NUNCA describir la leyenda de un gráfico en texto.**
- **Citas del cliente «...»: literales, intactas.** El tono solo aplica a lo nuestro.

## Frase TLS (en ambas partes)
Bloque portada 3 líneas: **The Last System** · El sistema operativo de tu negocio · **Libertad para ti. Crecimiento para tu empresa.** En Parte 2 (propuesta), encima va la **frase de dolores**. Diagnóstico = subtítulo neutro.

## Matriz · objetivo
- Aro = nivel más alto por reglas (suelo E2 · automatizamos E4 · equipo E5 · meta empresa E6), **curado por cliente**. En el ejemplo: Dir/Ventas/Op/Fin **E5**, Equipo **E4**, Marca/Herr **E2**.

## Camino (orden de resolución) — vertical, Entrada/Salida ENCADENADAS
Salida de un área = entrada del siguiente. En el ejemplo: **Operaciones** → **Ventas** → **Finanzas** → **Equipo** → **Dirección** → **Herramientas** (último, bajo demanda). Marca fuera de foco.

## Parte 1 · Diagnóstico
Apertura "PARTE 1" · Portada (subtítulo neutro + TLS) · **Resumen ejecutivo 6 etapas** ⭐ (varias en curso; foot Hoy/Problema/Proyecto) · **Matriz de madurez + Camino** ⭐ · 7 hojas de área (area-sum arriba; tabla Qué pasa «citas»/Por qué/Cómo resolver; activos tenéis/foco/menor; al final Situación·Salto·Resultado con barra etapa→objetivo; cita en Operaciones) · **cierra en "Marca"** (sin hoja de Conclusiones propia).

## Parte 2 · Propuesta de consultoría
Apertura "PARTE 2" · Portada (frase dolores + TLS) · **"Resumen ejecutivo"** ⭐ = la solución, "4 servicios para una solución completa" + ia-strip + resultado global en cuadro · 1 hoja por servicio (sesiones + Incluye/No incluye + resultado en cuadro; BBDD dentro de S2) · timeline 9 encuentros (1 diagnóstico + 8 de trabajo) · equipo · **"Solución tras diagnóstico"** ⭐ (antes "Conclusiones"): siguiente paso → **propuesta económica en firme** (no una tercera persona) + **"oferta válida 14 días"**.
- **Resultados siempre en cuadro.** **Canal directo ≤48h** en S4 y económica.
- **IA con memoria de cada cliente: SÍ.** Agentes de IA a medida: NO (a futuro).

## Propuesta económica (doc aparte)
Oferta económica + contrato simplificado + siguientes pasos. Es el doc "en firme" al que remite el dossier.

## Servicios y sesiones (9 encuentros = 1 diagnóstico + 8 de trabajo)
- **S1 Consultoría de negocio (ses. 1–4):** 6 áreas, flujos comerciales/líneas/operaciones, roles. NO rediseños completos (proyecto propio).
- **S2 Consultoría tecnológica (ses. 2–4):** BBDD/paneles/vistas. NO sustituir/integrar herramientas.
- **S3 Ajustes a medida (ses. 5–9):** flujo por área + automatizaciones + **IA con memoria**. NO agentes a medida (a futuro).
- **S4 Capacitación (ses. 4–8):** capacitación + canal ≤48h. NO soporte ilimitado.
- Fuera (bajo demanda): Marca, captación, sustitución de herramientas, integraciones externas, agentes IA a medida.

## Diseño
A4, texto negro, sin sombras ni grises. Azul `#1a3a8a` (P1) + magenta `#c20069` (P2). Colores área: Dir `#7c3aed` · Ventas `#16a34a` · Op `#2563eb` · Fin `#ea7c14` · Equipo `#dc2626` · Marca `#db2777` · Herr `#475569`. Portada sin nombres.

## Flujo
1. Duplicar las 2 plantillas a `Oportunidades/<Cliente>/<fecha>/`. 2. Editar en Chrome (Editar textos → placeholders + fuentes). 3. "Descargar HTML editado" para guardar la versión del cliente. 4. "Exportar a PDF". 5. QA página a página.

## Render alternativo (lote/auditoría)
`"…Google Chrome" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=15000 --print-to-pdf=salida.pdf "file://$PWD/archivo.html"` → QA `pdftoppm -png -r 72`. Auditar tono (grep frases prohibidas) antes de cerrar.

## Deck S1
Alineado: frase TLS + lógica de objetivo + "Copiar resumen" con matriz hoy→objetivo. Las estructuras del dossier (camino, Situación·Salto·Resultado, resultados en cuadro, numeración por parte) no van en el deck.

## Pendiente
Revisión interna · cifra de la económica y plazo (14 días).
