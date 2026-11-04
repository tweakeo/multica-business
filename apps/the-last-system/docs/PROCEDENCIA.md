# Procedencia del código

The Last System se escribe **desde cero en Swift** (decisión 2 del plan). Del trabajo anterior se
aprovechan especificaciones y lógica, nunca código copiado. Este documento dice qué se porta, de dónde,
de quién es y con qué regla. Base: PLAN §3.5.

Abreviaturas: **FORK** = `<ruta al fork>` (fork de Multica «Mika Business»),
**PROG** = Programa v0.5, **BK** = `<copia de seguridad privada>`, **MWS** = espacio de trabajo
de Multica alojado.

## Regla de sala limpia

1. **Se puede leer y portar** solo el código cuyo autor (según `git log`) es Manuel Trigo / Manu.
   Antes de abrir un fichero del fork, compruébalo:
   ```sh
   git -C <ruta al fork> log --format=%an -- <fichero> | sort | uniq -c
   ```
   Si aparece cualquier otro autor, el fichero **no se abre**.
2. **El código de LeonMAG no se abre** mientras se programa. Su comportamiento ya está especificado en
   el plan y se reimplementa solo desde ahí (ver tabla).
3. **Portar es reescribir**: se lee la lógica y se escribe Swift idiomático. No se copian bloques, ni
   comentarios, ni nombres de variables por inercia.
4. Cada fichero Swift portado lleva una **cabecera de procedencia** y una fila en el registro de abajo:
   ```swift
   // Procedencia: lógica portada de FORK server/internal/biz/layout.go (Manuel Trigo). Ver docs/PROCEDENCIA.md.
   ```
5. **Los datos reales nunca entran en el repositorio.** Los scripts privados de BK se leen como
   especificación del importador; ni ellos ni sus salidas se versionan. Los tests usan fixtures sintéticas
   y la empresa ficticia «Asesoría Ribera».

## Orígenes

Autoría comprobada con `git log --format=%an` el 21/10/2026 sobre el fork en `464f37bec`.

| Origen | Autor | Cómo se usa | Dónde aterriza |
|---|---|---|---|
| FORK `server/internal/biz/folder_human.go` (+ `folder_human_test.go`) | Manuel Trigo | Se lee y se porta | TLSCore · formato y lectura de la carpeta |
| FORK `server/internal/biz/layout.go` | Manuel Trigo | Se lee y se porta (preset humano) | TLSCore · `Layout` |
| FORK `server/internal/biz/writer.go` | Manuel Trigo | Se lee y se porta (protocolo de escritura segura, F1) | TLSCore · `VaultWriter` |
| FORK `server/internal/biz/{metas,portal,library,databases}.go` | Manuel Trigo | Se leen y se portan | TLSCore · dominio (F2) |
| FORK `packages/core/biz/pace.ts` | Manuel Trigo | Se porta el algoritmo de ritmo | TLSCore · métricas (F2) |
| FORK `scripts/tls/the-last-fechas.mjs` | Manuel Trigo | Se porta | TLSImport · fechas (F3) |
| FORK `scripts/tls/tls-ocr.swift` | Manuel Trigo | Se porta | TLSImport · OCR (F3) |
| FORK `server/internal/biz/kpi.go` | Mixto (LeonMAG y Manuel Trigo) | **No se abre.** Solo la lista de códigos KPI recogida en el plan (§4.4), como hechos | `kpi.json` |
| FORK `docs/tls/FORMATOS.md` | Mixto (LeonMAG y Manuel Trigo) | Solo los formatos recogidos en el plan (§4), como hechos | — |
| FORK `server/internal/biz/service.go` | LeonMAG | **Sala limpia.** Se reimplementa desde PLAN §5.2 (orden de autorización) | TLSCore · `Autorizador` |
| FORK `server/internal/biz/events.go` | LeonMAG | **Sala limpia.** Desde PLAN §4.7 (reglas de eventos) | TLSCore · `Rule` |
| FORK `server/internal/biz/delivery.go` | LeonMAG | **Sala limpia.** Desde PLAN §4.3 (`PlantillaEntrega`) y §5.3 (hash de aprobación) | TLSCore |
| FORK `server/internal/biz/finance.go` | LeonMAG | **Sala limpia.** Desde PLAN §4.6 (conciliación e `import_hash`) | TLSCore · banco |
| FORK `scripts/tls/build-dmg.sh` | LeonMAG | **Sala limpia.** `scripts/build-dmg.sh` se escribió solo desde PLAN §9 | `scripts/build-dmg.sh` |
| FORK `apps/macos/project.yml`, `apps/macos/TLS/**` | LeonMAG | **Sala limpia.** `project.yml` reescrito desde PLAN §3.1 | `project.yml`, `App/` |
| PROG `core/**`, `spec/capacidades.yaml`, `core/sql/{02,05,08,13,14}-*.sql` | Manu (confirmado el 21/10/2026: único autor) | Se portan los algoritmos (tarjetas, etapa, cuello, chequeos). `capacidades.yaml` va con su LICENSE Apache-2.0 | TLSCore, `App/Recursos/` |
| PROG `core/vault.js` (líneas 340–392, gramática TOK_FINAL) | Manu | Se porta como `ChecklistParser` (F2) | TLSCore |
| `vault-os/nucleo/{escribir,vault,servidor}.js` | Manu | Patrón (escritura, vigilancia) | TLSCore · `VaultWatcher`, `VaultWriter` |
| MWS `agentes/*.md`, `agent-{cartero,explorador}.md`, `autopilots.json` | Agentes de Manu | Se reescriben como instrucciones de rol (F4) | TLSAgents |
| BK `*.py` (`fase2_verificar.py`, `fase2_enlaces.py`, `mapa-migracion.csv`) | Manu | Lógica del importador e inventario. **Privados: no se versionan** | TLSImport |
| `<repositorio privado del manual>` (MANUAL-TLB) | Por confirmar (no figura en PLAN §3.5) | Se copia una vez | `App/Recursos/Manual/` |
| «Asesoría Ribera» (`~/TLS Empresas/DEV - Asesoría Ribera`) | Por confirmar (empresa ficticia; no figura en PLAN §3.5) | Entrada del conversor y de los golden | `App/Recursos/Ejemplos/` |

## Registro de ficheros portados

Una fila por fichero Swift con cabecera de procedencia. La añade quien porta.

| Fichero | Origen | Autor del origen | Fase |
|---|---|---|---|
| `scripts/build-dmg.sh` | PLAN §9 (sala limpia; el script del fork no se abrió) | — | F0 |
| `Packages/TLSKit/Sources/TLSCore/Formato/VaultLayout.swift` | FORK `server/internal/biz/layout.go` (preset humano; la ruta privada fija del original **no** se portó: lo privado sale de `.tls/`) | Manuel Trigo | F0 |
| `Packages/TLSKit/Sources/TLSCore/Formato/AreaReader.swift` | FORK `server/internal/biz/library.go` (`parseSystem`) | Manuel Trigo | F0 |
| `Packages/TLSKit/Sources/TLSCore/Formato/LinkParser.swift` | FORK `server/internal/biz/databases.go` (`noteRefs`) | Manuel Trigo | F0 |
| `Packages/TLSKit/Sources/TLSCore/Escritura/WriterClaim.swift` | FORK `server/internal/biz/writer.go` (patrón de escritor único: `.tls/escritor.json` + `flock`) | Manuel Trigo | F1 |
| `Packages/TLSKit/Sources/TLSCore/Tareas/ChecklistParser.swift` | PROG `core/vault.js` (líneas 340–407: gramática TOK_FINAL, `leerTareasChecklist` y `leerNotasTareas`) | Manu | F1 |
| `Packages/TLSKit/Sources/TLSCore/Dominio/Reglas.swift` | PROG `core/reglas.js` (una regla por evento y función, «si ya existe, no se repite») y PLAN §4.7 / SISTEMAS §3.3–3.4. FORK `events.go` (LeonMAG) **no se abrió** (sala limpia) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Dominio/EventDeriver.swift` | PROG `core/reglas.js` (catálogo de eventos) y PLAN §4.7; los eventos se deducen de comparar fichas, no de tablas | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Dominio/Expediente.swift` | PROG `core/expediente.js` (números, línea de tiempo de hechos con la regla del «alta», alertas) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Finanzas/LectorFiscal.swift` | PROG `core/fiscal.js` (leer fecha, importe, número, cliente o proveedor, tipo fiscal y categoría del nombre del original; «lo que el nombre no dice, no se dice») y `core/sql/11-fiscal.sql` (tabla de tipos fiscales) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Finanzas/TrimestreFiscal.swift` | PROG `core/sql/11-fiscal.sql` (`periodo_trimestre`: plazo, domiciliación y precierre) y `core/importar-notion.js` (`calcular303`: reglas por tipo fiscal y autoliquidación intracomunitaria); el 130, el 111 y el 115 se escribieron desde PLAN §6.5 | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Finanzas/PaqueteGestoria.swift` | PROG `core/fiscal.js` (`leerCarpetaFiscal`: solo justificantes, proveedor por subcarpeta); la forma del paquete sale de la plantilla «Índice del paquete trimestral» | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/CatalogoPrograma.swift` | PROG `spec/capacidades.yaml` y `core/sql/{02-semillas,10-tlb,13-estructura,14-calibracion}.sql` (solo los datos, en `Recursos/Programa/`; el código Swift es nuevo) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/KPIEvaluador.swift` | PROG `core/sql/08-metricas.sql` (`metrica_valor`: cada número medido en el periodo de su objetivo) y las fórmulas de «Cómo se mide» del `Metas.md` de Ribera (hechos). FORK `kpi.go` **no se abrió** (sala limpia) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/RitmoCalculador.swift` | PROG `core/sql/08-metricas.sql` (`ritmo_objetivos`: esperado = meta × parte del periodo; umbrales 1,05 · 0,95 · 0,80 · 0,55) y `core/sql/05-diseno.sql` (`ritmo_empresa`, capado a 100). «El área toma el ritmo de su número más atrasado»: PLAN §9 F2 y SISTEMAS DI3 (FORK `pace.ts` no se abrió) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/EtapaCalculador.swift` | PROG `core/sql/03-vistas.sql` (`etapa_por_area`, `etapa_negocio`), `core/sql/14-calibracion.sql` (solo cuenta lo declarado), `core/sql/10-tlb.sql` (`siguientes_pasos`), `core/madurez.js` (`progreso`, objetivo E5) y `core/consultoria.js` (`loQueFalta`, el porqué de la etapa) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/Chequeo.swift` | PROG `core/consultoria.js` (`COMPROBACIONES` y el orden de `comprobar`; DIR-03 queda en atención por PLAN Anexo A). Los 7 chequeos, de SISTEMAS DI2 | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/SaludCalculador.swift` | PROG `core/salud.js` (`calcularSalud`: seis dimensiones; sin dato, una señal de que falta, nunca un «bien») | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/CuelloCalculador.swift` | PROG `core/sql/05-diseno.sql` (`cuello_botella`: presión y motivo), `core/madurez.js` (`matriz`, `camino`, `TRAMO`) y `core/consultoria.js` (veredicto determinista) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/TarjetaBuilder.swift` | PROG `core/tarjetas.js` (generadores, cinco preguntas, `PESO`, `nivelPrioridad`, `impactoDe`, `plazoDe`, niveles de rol, mazos por área) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/Agenda.swift` | PROG `core/tiempo.js` (`agenda`: un solo eje con su carga frente al tope; lo atrasado aparte) | Manu | F2 |
| `Packages/TLSKit/Sources/TLSCore/Metricas/LecturaArea.swift` | PROG `core/lecturas.js` (lectura sin modelo y su firma) y `core/areas.js` (periodos y números de «Análisis») | Manu | F2 |

Autoría de las filas del fork comprobada de nuevo con `git log --format=%an` el 22/10/2026 sobre el fork en `712b6702b`
(`writer.go`: un único autor, Manuel Trigo). La de PROG la comprobó el rol que la portó (8 commits, todos de Manuel
Trigo); PROG vive en iCloud y la integración no lo abre.

El resto del código de F1 (escritura, enlaces, plantillas, tareas, Adoptar, conversor G2, asistentes) es nuevo: no
porta código de ningún origen. `Sources/TLSCore/Recursos/Plantillas/` son las plantillas de `docs/propuesta/plantillas`
(propuesta v2, escrita para este proyecto).

## Estándar de Programa incluido en la app (F2 · números)

En `Packages/TLSKit/Sources/TLSCore/Recursos/Programa/` (recurso del paquete TLSCore, como las plantillas). Autor de PROG:
Manu (confirmado como único autor). Solo se leyeron `core/**` y `spec/**`; ni `datos/` ni los vaults.

| Fichero | Origen | Licencia | Notas |
|---|---|---|---|
| `capacidades.yaml` | PROG `spec/capacidades.yaml`, copiado sin cambios (SHA-256 `0fb3b5e4d0e5a15ac10d13eee9aae7b4103a3bef96180896c70c752078896027`) | Apache-2.0 (`LICENSE` al lado, copia de `spec/LICENSE`) | 78 capacidades: el estándar |
| `semillas.json` | PROG `core/sql/02-semillas.sql` (áreas, roles, etapas, módulos, rutinas) y `core/sql/10-tlb.sql` (qué toca y señal de cada etapa), convertidos con un guion de un solo uso | Del proyecto | Sin los colores de área (manda Mosaico v2) |
| `sistemas-std.json` | PROG `core/sql/13-estructura.sql` (`sistemas_std`) y `core/sql/14-calibracion.sql` (capacidades de cada sistema) | Del proyecto | 24 sistemas, 4 por área |
| `kpi.json` | Hechos: la tabla y «Cómo se mide» del `Metas.md` de Ribera (21 códigos, contados el 23/10/2026) y los números nuevos de SISTEMAS §2.5 y DI1 (8) | Del proyecto | FORK `kpi.go` no se abrió |

## Recursos de terceros incluidos en la app (F1 · interfaz)

Letras de Mosaico v2 (`docs/propuesta/DISENO-MOSAICO-V2.md` §1.9), descargadas el 22/10/2026 del repositorio oficial
de Google Fonts (`github.com/google/fonts`, rama `main`) sin modificar, con su licencia junto a cada una. Van en
`Packages/TLSKit/Sources/TLSDesign/Recursos/Fuentes/` (recurso del paquete: así se registran igual en la app y en
`swift test`), no en `App/Recursos/Fuentes/`.

| Fichero | Origen | Licencia | SHA-256 |
|---|---|---|---|
| `SpaceGrotesk/SpaceGrotesk[wght].ttf` | `ofl/spacegrotesk` | SIL OFL 1.1 (`SpaceGrotesk/OFL.txt`) | `acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72` |
| `DMSans/DMSans[opsz,wght].ttf` | `ofl/dmsans` | SIL OFL 1.1 (`DMSans/OFL.txt`) | `8cd08d97e89c24d0aa92edd2f0f4c8ee6195eee9b7c9f154865a58b02f0c1c0d` |
| `DMSans/DMSans-Italic[opsz,wght].ttf` | `ofl/dmsans` | SIL OFL 1.1 (`DMSans/OFL.txt`) | `22259c0cc8237221b80f44c76ba8d36e6bce3cda72779f5b2773643d499720ae` |
| `JetBrainsMono/JetBrainsMono[wght].ttf` | `ofl/jetbrainsmono` | SIL OFL 1.1 (`JetBrainsMono/OFL.txt`) | `48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda` |

Comprobado al incluirlas: Space Grotesk trae cifras tabulares (`tnum`); la DM Sans de Google Fonts **no** (ni `tnum`
ni cifras de ancho fijo por defecto), así que `cifraFila` usa las cifras tabulares de la letra del sistema
(`DesignTests`/`MosaicoDesignTests.cifrasTabulares` lo vigila).

## Manual y tutorial (F3 · rol tutorial)

En `App/Recursos/Manual/` (recurso de la app, carpeta `Recursos/Manual` del bundle).

| Fichero | Origen | Autor | Cómo se usa |
|---|---|---|---|
| `MANUAL-TLB.md` | `git --git-dir=<repositorio privado del manual> show HEAD:tlb/manual/MANUAL-TLB.md`, copiado **una vez** el 23/10/2026 sin cambios (HEAD `64cc1f0`, último cambio del fichero `684e9ca`; SHA-256 `1ac9ec4f5623d254aac40ce9195027712e7abdc4314612d59b5e564e9791e9a6`) | Manuel Trigo (único autor según `git log --format=%an`) | Fuente del manual corto. Viaja en la app, pero no se enseña en la v1 (PLAN §12: «el TLB largo dentro de la app», fuera). `ManualTests.copiaDelMetodo` comprueba que no ha cambiado |
| `Manual corto.md` | Escrito para la app (F3) a partir de PLAN, SISTEMAS y el método TLB de Manu | Del proyecto | Ventana `Window("manual")` y «Saber más» de cada paso del tutorial y de la puesta en marcha (`paso-<paso>`) |
| `De dónde salen las ideas.md` | Escrito para la app (F3): página de contraste con las ideas de método que la app adopta (1-3-1, entrevistador, seguimiento 7/14/21/30, traspaso en cuatro fases, una sola colección de tareas) | Del proyecto | **Ningún texto viene de Blash**: no se abrió ningún material del curso; cada idea está dicha con palabras propias, a partir de cómo la describen PLAN y SISTEMAS («idea de Blash, reformulada») |

Textos del tutorial (`Sources/TLSUI/Tutorial/RecorridosTutorial.swift`): propios, del proyecto.

## Importar de Multica (F3 · rol tutorial)

`Sources/TLSImport/Multica/**` está escrito desde cero a partir de la orden de lectura que da PLAN §9 F3 y el formato de
la ficha de tarea (PLAN §4.2). No se abrió ningún fichero del fork ni de Multica, ni se lanzó su programa de verdad:
las pruebas usan un programa falso con JSON inventado. Las órdenes de perfiles (`profile list --output json`) y el
formato exacto de `workspace list` no se pudieron comprobar sin lanzarlo: la lectura acepta varias formas (ver
`docs/F3-CONTRATOS.md`, sección del rol tutorial).

## Ordenar lo que tienes (F3 · rol importador)

`Sources/TLSImport/Importar/**`. Portar es reescribir: se leyó la lógica y se escribió Swift nuevo (cada fichero portado
lleva su cabecera de procedencia). De BK solo se leyeron los tres scripts de abajo y la **cabecera** de
`mapa-migracion.csv` (`origen,destino,accion,motivo,conflicto`); ni sus filas (rutas reales) ni las copias `fase*-antes`.
Ningún nombre, ruta ni dato real de esos scripts está en el código ni en las pruebas (empresa ficticia y «Expediente
privado» como carpeta privada).

| Origen | Autor | Cómo se usa | Dónde aterriza |
|---|---|---|---|
| FORK `scripts/tls/tls-ocr.swift` (último cambio `d4c63197e`; SHA-256 `4f835a41fc7078ea4f6267bc4f3956eb2f01ada24b0995cda5852cfb60cfc832`) | Manuel Trigo (único autor según `git log --format=%an`) | Se lee y se porta: Vision, español e inglés, precisión alta. Ya no se compila un ejecutable aparte: es un servicio (ImageIO para imágenes, CoreGraphics para pintar la página del PDF a 200 ppp) | `Importar/OCRService.swift` |
| FORK `scripts/tls/the-last-fechas.mjs` (último cambio `d4c63197e`; SHA-256 `b2d1dee71c56cabafc56d178fb2f947c520fde60200d875d3cb940d1b245bc30`) | Manuel Trigo (único autor) | Se lee y se porta: orden de fuentes, las cuatro formas de fecha, etiquetas y «no es la del documento», orden de EE. UU., fecha del nombre y de la carpeta, filas `manual` intocables. Cambios: PDFKit en vez de `pdftotext`/`pdfinfo`, lector ZIP propio en vez de `unzip`, año mínimo configurable (por defecto, hace diez años; el original fijaba 2023) y `ruta` relativa a Finanzas, como el ejemplo y el conversor | `Importar/DocumentDater.swift`, `Importar/FechasDeDocumentos.swift` |
| BK `fase2_enlaces.py` | Manuel Trigo | Se lee como especificación: resolver en el sitio viejo, seguir el registro de movimientos, reescribir relativo al sitio nuevo con el mismo estilo (`%20` o `<…>`), enlaces absolutos dentro del origen y lista de los que no resuelven | `Importar/LinkRewriter.swift` (lo traído de fuera); dentro de la carpeta lo hace `LinkRefactor` del núcleo |
| BK `fase2_verificar.py` | Manuel Trigo | Se lee como especificación: cada fichero de la foto de antes en su destino (por prefijo y en orden), tamaño y SHA-256, los editados a propósito aparte y el recuento | `Importar/Verificador.swift` |
| BK `mapa-migracion.py` y la cabecera de `mapa-migracion.csv` | Manuel Trigo | Solo el esquema y la idea de cada acción (mover, renombrar, retirar a Archivo, no migrar, mantener fuera, duplicados de iCloud con hash, trimestre por la fecha del documento) | `Importar/MapaImportacion.swift`, `ZonaPreparacion.swift`, `HeuristicClassifier.swift` |

## Motor de asistentes (F4 · rol motor)

`Sources/TLSAgents/{Motor,Runtime,Chat}/**` está escrito para la app a partir de PLAN §5.3 y lo de la sonda de F1. Solo
se portó (leyendo y reescribiendo en Swift) lo de abajo; de `PROG/core/agentes.js` se leyó el principio («sin clave, lo
determinista sigue funcionando») sin portar código. Nada de `<ruta al fork>`.

| Origen | Autor | Cómo se usa | Dónde aterriza |
|---|---|---|---|
| `PROG/core/hablar.js` (Programa v0.5) | Manu | Se porta el enrutador sin modelo: las 14 intenciones con sus patrones, su orden («las que escriben ganan», `cliente` la última), «enruta, no contesta» y «no escribe: propone». Las respuestas ya no son SQL: salen de las métricas, las tareas y el dominio del núcleo, con «Sin dato» en vez de 0 y sin nada privado | `Chat/EnrutadorDeIntenciones.swift` |

## Asistentes como producto (F4 · rol roles)

`Sources/TLSAgents/Roles/**`, `App/Recursos/Asistentes/*.md`, `Sources/TLSAgents/Simulado/Grabaciones/**` y la parte de
asistentes de Ribera. Portar es reescribir: de Programa v0.5 se leyó la lógica y los datos que se citan y se escribió
texto y Swift nuevos. Las instrucciones originales de los agentes de Multica (MWS `agentes/*.md`,
`agent-{cartero,explorador}.md`, `autopilots.json`, en la tabla de orígenes) **no se abrieron** (este rol solo podía
leer Programa v0.5); las instrucciones se escribieron desde PLAN §5.1, SISTEMAS §2.4 y §6 y las fuentes de abajo. Nada de `<ruta al fork>` ni de cursos (ningún texto de Blash, Nico ni TLB).

| Origen | Autor | Cómo se usa | Dónde aterriza |
|---|---|---|---|
| PROG `core/sql/02-semillas.sql` (roles: `mision` y `pregunta_fija`; miembros agénticos `ag-dir`, `ag-ven`, `ag-ent`, `ag-fin`, `ag-mar`, `ag-equ`: `solo`, `con_ok`, `nunca`) | Manu | Las preguntas fijas son las del estándar; las misiones y lo que cada asistente hace solo, con OK o nunca, reescritas y ampliadas con PLAN §5.1 y SISTEMAS §6.1 | `Roles/PerfilesDeSerie.swift`, `App/Recursos/Asistentes/*.md` |
| PROG `core/agentes.js` (el asistente comprueba sus permisos antes de actuar, todo queda en la bitácora con su coste, responde corto y sin inventar, «si te falta un dato, dilo en vez de suponerlo») | Manu | Solo las ideas, reescritas en las instrucciones (el control de permisos lo hace el Autorizador, no el asistente) | `App/Recursos/Asistentes/*.md` |
| PROG `spec/capacidades.yaml` y `kpi.json` del núcleo (ya en `Recursos/Programa`) | Manu | Los códigos de funciones y números de cada perfil (se comprueba en las pruebas que existen) | `Roles/PerfilesDeSerie.swift` |

| Fichero | Origen | Autor del origen | Fase |
|---|---|---|---|
| `Packages/TLSKit/Sources/TLSAgents/Roles/PerfilDeAsistente.swift` | PROG `core/sql/02-semillas.sql` (modelo de miembro agéntico: rol, permisos `solo`/`con_ok`/`nunca`) y PLAN §5.1 | Manu | F4 |
| `Packages/TLSKit/Sources/TLSAgents/Roles/PerfilesDeSerie.swift` | PROG `core/sql/02-semillas.sql` y `core/agentes.js`; PLAN §5.1 y SISTEMAS §6.1 | Manu | F4 |
| `App/Recursos/Asistentes/{mika,comercial,implementador,contable,marca,equipo,cartero,ordenador}.md` | Ídem, más SISTEMAS §2.4 (ciclo de un sistema) y VIDEOS.md (solo el resumen ya hecho en la propuesta) | Manu | F4 |
