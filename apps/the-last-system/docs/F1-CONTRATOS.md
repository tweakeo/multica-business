# F1 · Contratos entre módulos

F1 = «Editar como en Obsidian»: la app escribe **solo en copias y en la demo** (`clase: copia | demo`). La carpeta
real (`clase: real`) sigue en solo lectura hasta F6. Especificación: `docs/PLAN.md` §4.8 y §9 F1, y la propuesta v2
(`docs/propuesta/SISTEMAS.md`, `PLANTILLAS.md`), que manda donde difieran. Lo de F0 sigue en `docs/F0-CONTRATOS.md`:
aquí solo se añade. Como en F0, las firmas públicas se pueden **ampliar**, no cambiar; un cambio de firma se anota en
«Cambios pedidos» al final.

## Propiedad de ficheros en F1

| Módulo | Ficheros | Dueño |
|---|---|---|
| Escritura | `Sources/TLSCore/Escritura/**`, `Tests/TLSCoreTests/Escritura/**` | escritor |
| Enlaces, plantillas, tareas, Adoptar | `Sources/TLSCore/{Refactor,Plantillas,Tareas,Adoptar,Recursos}/**` y sus pruebas | funciones |
| Conversor G2 y conformidad | `Sources/TLSImport/Convertir/**`, `Sources/tls-tool/ConvertirG2.swift`, `Tests/Conformidad/**`, `App/Recursos/Ejemplos/**`, `scripts/conformidad.sh` | conversor |
| Asistentes (sonda) | `Sources/TLSAgents/**`, `Tests/TLSAgentsTests/**`, `scripts/verificar-sandbox.sh` | sonda |
| Interfaz | `Sources/TLSUI/**`, `Sources/TLSDesign/**`, `App/Sources/**` | interfaz (espera al diseño elegido) |
| Integración | `Package.swift`, `VaultService.swift`, `Formato/**`, `tls-tool/**`, `Makefile`, `docs/**` | integración |

## Garantías de F1 (criterios del PLAN §9 F1)

1. Leer y reescribir sin cambios cada `.md` y `.csv` de Ribera y de la fixture da 0 bytes de diferencia
   (con el lector del núcleo y con `FrontmatterDocument`/`CSVDocument`).
2. `mergeFrontmatter` cambia solo las líneas de esas claves (caso dorado y 1.000 casos aleatorios).
3. Tras 200 operaciones aleatorias, el índice reconstruido es igual al incremental.
4. Con el proceso muerto a mitad de un plan (`kill -9` simulado en cada punto y 36 veces al azar) no queda ningún
   fichero a medias, la copia previa existe y no aparecen falsos conflictos; al abrir se termina lo pendiente.
5. Editor: lo verifica la interfaz cuando exista (pendiente del diseño). El guardado de una persona no exige `hash_app`.
6. Un cambio de fuera con una edición abierta crea una tarjeta de conflicto con las dos versiones recuperables; si
   fuera solo cambian propiedades o se añade Actividad, se fusiona sin aviso.
7. Convertir Ribera dos veces da el mismo hash de árbol (igual al del ejemplo versionado), 0 errores del validador y
   ninguna nota sin tipo.
8. Sandbox de asistentes con Claude Code real (`scripts/verificar-sandbox.sh`).

Además:
- **Nunca se borra nada.** No existe la operación de borrar: retirar mueve a `Archivo/<misma ruta>`; deshacer una
  creación la retira a `Archivo/`. Deshacer solo quita, con `rmdir` (que no puede quitar nada que tenga dentro), las
  carpetas vacías que creó el propio plan (`JournalPlan.carpetas`). `Archivo/` se escribe aunque no se haya copiado
  (`exclusionesCopia`): se excluye por tamaño, no por privado.
- **La carpeta real no se escribe:** ni notas, ni `.tls/escritor.json`, ni cerrojo, ni estado. `VaultWriter.open`
  lanza `WriteError.carpetaReal` con `clase: real`, con `.tls/config.yaml` que diga `clase: real` o con una ruta
  dentro de iCloud Drive.
- **Renombrar o mover actualiza todos los enlaces** (wikilinks con y sin alias, sección e incrustados; Markdown
  relativos con `%20`, `<…>`, sin `.md` o con `#sección`; enlaces en propiedades y listas; rutas en columnas de CSV y
  en los ajustes de `.tls/`). Solo cambia el destino de cada enlace; el resto de bytes, no. Todo va en un único plan
  (todo o nada) que se deshace de una vez dejando los mismos bytes. También el `"file"` de los lienzos (`.canvas`)
  y las rutas de los ajustes escritas como plantilla (`{finanzas}/Privado`), que siguen siendo plantilla.
- **Cada enlace va donde lo lleva Obsidian** (regla de `getLinkpathDest` de Obsidian 1.7, ver `LinkResolver`): ruta
  exacta desde la raíz; en un wikilink la ruta escrita es obligatoria (`[[Vieja/nota]]` con la nota en otra carpeta
  está roto); con nombres repetidos, primero las que cuelgan de la carpeta de la nota que enlaza y, dentro de cada
  grupo, la de ruta más corta; si las dos primeras empatan, ambiguo. Al renombrar o mover, si el nombre deja de ser
  único, el enlace se escribe con su ruta. Al **crear** una nota con un nombre que ya existe (`Proyecto.md`,
  `Contrato.md`, una colaboración que se llama como el contacto…), los enlaces que ya había se reescriben con su ruta
  en el mismo plan (`LinkRefactor.protegerEnlaces`), así que ninguno cambia de destino.
- **Nombres que no rompen enlaces:** renombrar rechaza `/ : \ # ^ [ ] |` y las plantillas los sustituyen por espacios.
- **Una ficha `.md` por tarea** (`…/Tareas/t-NNNN-slug.md`, nombre de 60 caracteres como mucho también si se crea
  con `PlantillaMotor`), con el contador en `.tls/secuencias.json`.
- **Facturas:** la app prepara; la emisión oficial la hace otra herramienta (sin cambios en F1).

## TLSCore · escritura (público)

- `VaultWriter` (actor con cola serie propia; la sección crítica no tiene ningún `await`):
  - `static func open(entry: VaultEntry, root: URL, options: Options = Options()) async throws -> VaultWriter`.
    Recupera lo pendiente al abrir (`lastRecovery: RecoveryReport{completados, aplicados, abandonados, conflictos}`).
  - `Options(stateDirectory:appSupport:app:now:diasDeCopias:)`; `static var defaultAppName`.
  - `setOnApplied(_: (@Sendable ([VaultPath]) -> Void)?)`, `appHash(_:) -> String?`, `lastUndoable() -> UndoInfo?`,
    `recover() throws -> RecoveryReport`, `close()`.
  - `nonisolated`: `entry`, `root`, `stateDirectory`, `recentWrites: RecentWrites`, `conflicts: ConflictRegistry`.
  - `apply` y `undoLast` son internas: **solo se escribe a través de `CommandBus`.**
- `CommandBus(writer:)`:
  - `ejecutar(_ comando: Comando, autor: Autor) async throws -> WriteResult`, `ejecutar(_ plan: WritePlan)`.
  - `ultimoDeshacible() async -> UndoInfo?`, `deshacer(autor:) async throws -> WriteResult`.
  - `resolverConflicto(_:eleccion: EleccionConflicto (.mia | .otra | .combinada(String)), autor:)`,
    `descartarDuplicado(_:quedarmeConElDuplicado:autor:)`, `resolverICloud(_:quedarmeCon:provider:autor:)`.
  - `Comando`: `crear`, `cambiarPropiedades(poner:quitar:)`, `guardarNota(base:texto:)`, `anadirASeccion`,
    `sustituirSeccion(baseHash:)`, `sustituirCuerpo(baseHash:)`, `anadirLinea`, `guardarFila(fila:clave:)`,
    `cambiarCeldas`, `anadirFilaATabla`, `mover`, `retirar`.
- `WriteOp`: `create`, `mergeFrontmatter(set:unset:)`, `appendToSection`, `replaceSection(baseSectionHash:)`,
  `replaceBody(baseHash:)`, `saveText(base:text:)`, `appendLine`, `upsertCSVRow`, `setTableCells`, `appendTableRow`,
  `editRanges(edits:baseHash:)`, `move`, `retire(apartado:)`; ayudas `create(_:text:)`, `appendToSection`,
  `retire(_:)`, `replaceText(_:base:text:) -> WriteOp?`; `path`, `resumen`.
- `WritePlan(id:autor:descripcion:ops:)`, `Autor` (`.persona(String) | .sistema | .agente(String)`, `etiqueta`,
  `esPersona`, `init(etiqueta:)`), `TextEdit(offset:length:replacement:)`, `Movimiento`, `UndoInfo`,
  `WriteResult{planID, estado: .hecho | .sinCambios | .conflicto(ConflictRecord), cambiadas, creadas, movidas, hashes}`
  (`hecho`, `conflicto`), `WriteError` (con textos en español).
- Documentos que reescriben sin tocar el resto de bytes: `FrontmatterDocument(text:)`/`init?(data:)` (`set`, `unset`,
  `merge(set:unset:)`, `replaceBody`, `value`, `keys`, `rawLines`, `frontmatterBlock`, `canonicalOrder`);
  `CSVDocument` (`upsert(_:key:protectManual:) throws -> UpsertResult`, `row(key:value:)`, `isManual`);
  `TableSelector`, `MarkdownTable.rows(in:selector:)`, `MarkdownSections.titles/content/hash(of:in:)`,
  `ContentHash.of(_:)`.
- `RecentWrites` (`register`, `isOwn`, `filterExternal`), `WriterClaim` (`read(root:)`, `lockURL(root:appSupport:)`,
  `acquire(…)`, `release()`, `Info`; fichero `.tls/escritor.json` + `flock` en `<appSupport>/locks/`).
- `WritePolicy.escrituraInicial(para:)`, `comprobar(_:root:)`, `clase(declaradaEn:)` (`nil` si no hay
  `.tls/config.yaml` o no dice `clase`; **`.real`** si existe y no se puede leer: enlace simbólico, solo en iCloud,
  YAML roto o clase desconocida); `VaultRegistry.permitirEscrituraEnCopias() throws -> [UUID]`: **solo en el primer
  arranque con F1** (sin `escritura.json`) abre las copias de F0; después, una copia en solo lectura («Ver sin tocar»)
  sigue así. La real, siempre `bloqueada`.
- `CommandBus.deshacer` lanza además `noPermitidoAsistente` (un asistente solo deshace lo suyo), `enlaceSimbolico` y
  `rutaNoPermitida` (las mismas reglas de rutas que `PlanCompiler`, también al recuperar); `resolverICloud` lanza
  `versionNoDisponible` si llegó otra versión después de la tarjeta (no se marca nada sin copia). Un asistente o el
  sistema no pueden `sustituirSeccion` en una nota que no está como la dejó la app (`soloAnadidos`, PLAN §4.8).
- Compare-and-swap real al escribir: el temporal se intercambia con `renamex_np(RENAME_SWAP)` y se comprueba la huella
  de lo que sale; si alguien guardó en ese momento, se vuelve a intercambiar y es `cambioExterno` (en volúmenes sin
  intercambio, segunda comprobación y `replaceItemAt`). Se conservan permisos, atributos extendidos y fecha de
  creación. Volver atrás un plan fallido y recuperar un plan que no llegó a empezar es todo o nada y nunca pisa lo
  escrito fuera.
- Conflictos y duplicados: `ConflictRegistry` (`pendientes`, `todos`, `record`, `registrar`, `datos(de:root:)`,
  `marcarResuelto`, `folder(for:)`; guarda en `<estado>/conflictos.json`), `ConflictRecord`, `ConflictVersion`,
  `ConflictLocation`; `DuplicateDetector(root:excluidas:layout:)` (`scan()`, `scan(paths:)`, `registrar(_:en:)`);
  `ICloudConflicts.scan(_:root:registry:provider:)`, `ConflictVersionProvider`, `SystemFileVersions`,
  `ConflictVersionInfo`.

Estado fuera de la carpeta (`AppLocations.vaultState(id)`): `diario.jsonl`, `diario/`, `copias/AAAA-MM-DD/<plan>/`
(30 días), `conflictos.json`, `index.sqlite`. Dentro de la carpeta la app solo crea `.tls/escritor.json`
(y, mientras dura un cambio de solo mayúsculas, el intermedio `.tls-renombrar-*`).

## TLSCore · enlaces, plantillas, tareas y Adoptar (público)

- `VaultSnapshot.read(root:layout:excluded:)`, `read(entry:root:)`; `text`, `data`, `existing`, `isDirectory`,
  `resolver`, `notes`, `textPaths`, `frontmatter`, `idIndex()`, `static isTemplatePath(_:)`, `settingsFiles`.
- `LinkScanner.scan(_:) -> [LinkOccurrence]` (rangos en bytes, `<…>`, lugar cuerpo/propiedad, comillas YAML, línea).
- `LinkRefactor(snapshot:)` / `LinkRefactor(root:excluidas:)`:
  - `renombrar(_:a:opciones:)`, `mover(_:a:opciones:)`, `preparar(_ traslados: [Traslado], descripcion:opciones:extra:)`,
    `arreglarMovimientoExterno(_:opciones:)` → `RefactorPreview`.
  - `protegerEnlaces(alCrear: [VaultPath], opciones: Opciones = Opciones()) -> [WriteOp]`: ediciones que hay que poner
    en el mismo plan que la creación (lo usan `PlantillaMotor.preparar`, `TaskStore.crear` y `PlantillaInstalador`).
    `[]` si ningún nombre se repite.
  - `static aplicar(_:con: CommandBus, aunqueHayaProblemas: Bool = false) async throws -> WriteResult`.
  - `Opciones(autor:alias: .automatico | .siempre | .nunca, actualizarTextoVisible:columnasCSV:propiedadesRuta:conflictos:)`.
  - `RefactorPreview`: `descripcion`, `traslados`, `cambios: [CambioDeFichero]`, `enlaces`, `notas`, `filasCSV`,
    `sinDescargar`, `enConflicto`, `noEditables`, `problemas`, `plan`, `resumen`, `avisoHecho`, `esSeguro`.
  - `Traslado(de:a:)`, `CambioDeFichero`, `CambioDeEnlace` (`Lugar`: `cuerpo`, `propiedad`, `columna`, `ajustes`),
    `ProblemaDeEnlace`, `RefactorError`.
- `SaludDeEnlaces(snapshot:)`: `revisar()`, `revisar(_:) -> [EnlaceRevisado]` (`pendiente`, `ambiguo`, `flojo`),
  `arreglarFlojos(autor:)`, `nombres(de:)`, `mencionesSinEnlazar(de:)`, `enlazar(_:estilo:autor:)`.
- Plantillas: `PlantillaRegistro` (`deSerie`, `cargar`, `parse`, `subscript(id)`, `desde(tipo:)`, `deSistemas`, `ruta`),
  `PlantillaDef`, `PlantillaError`, `PlantillasDeSerie` (90 plantillas en `TLSKit_TLSCore.bundle`),
  `PlantillaMotor(snapshot:registro:opciones:)` (`preparar(Peticion) -> NotaPreparada`, `aplicar`,
  `insertarFragmento`, `variablesSinRellenar`, `rellenarPendientes`), `PlantillaInstalador(snapshot:).preparar(…)`,
  `ContextoPlantilla`, `NotaDeContexto`, `Reloj` (`sistema`, `deCarpeta`), `FormatosPlantilla`, `NombresDeFicha`,
  `Secuencias` (`leer`, `siguiente`, `mayorVisto`, `formatear`, `clave`, `op(_:en:)`).
- Reglas de nombre de `PlantillaMotor.preparar`:
  - Nombre fijo que ya existe (`Área`, `Empresa`, `Metas`, `Marca`, el plan de un servicio…):
    `PlantillaError.yaExiste(ruta)`; se completa la que hay con `aplicar` (SISTEMAS §5.6). Con `{{slug}}`, el
    siguiente libre en kebab (`lucia-ferrer-2`), nunca «(2)».
  - Versiones (`-v{{version}}`, ` v{{orden}}`): la mayor con ese mismo nombre en la carpeta, más uno (`renta-v3` con
    `renta-v1`, `renta-v2` y `trim-v1`); `version` en las propiedades es la misma. El resto de `{{orden}}`
    (`{{fecha}}-seguimiento-{{orden}}`) cuenta todas las de su tipo en la carpeta (PLANTILLAS §1.3).
  - Recibo: `numero` en la ficha y el nombre; `mayorVisto` también lee el nombre de los recibos. El presupuesto ya no
    gasta número al crear el borrador (se numera al aprobarlo).
- Tareas: `EstadoTarea` (`init?(leyendo:)`), `TareaArchivo`, `Tarea` (`esListaParaAgente(hoy:)`, `laborable`),
  `NuevaTarea`, `TaskStore(snapshot:reloj:)` (`tareas`, `tarea`, `carpeta(area:proyecto:)`, `siguienteNumero`, `crear`,
  `cambiarEstado(_:a:autor:persona:nota:soloEstado:)`, `anadirActividad`, `duplicados`, `renumerar`,
  `resolverDuplicados`, `correccionesDeUbicacion`, `corregir`), `TareaError`, `CorreccionDeUbicacion`,
  `ChecklistParser.parse(_:)`, `LegacyTasksMigrator(snapshot:reloj:)`.
- Adoptar: `Adopter(snapshot:).proponer() -> PropuestaAdopcion` (`identidades`, `relaciones`, `ambiguas`,
  `tareasHeredadas`, `planIdentidad(autor:)`, `planRelaciones(_:autor:)`, `resumen`).

## TLSCore · integración (añadidos de F1)

- `VaultService` (solo añadidos; sigue sin escribir nada):
  - `conectar(_ writer: VaultWriter, alEscribir: (@Sendable ([VaultPath]) -> Void)? = nil) async -> Bool`
    (`@discardableResult`): tras cada plan reindexa al momento lo que tocó y después llama a `alEscribir` con esas
    rutas (en la cola del índice). Devuelve `false` si el escritor es de otra carpeta.
  - `desconectar(_ writer: VaultWriter) async` (al pasar a solo lectura, antes de `writer.close()`).
  - `reindexar(_ paths: [VaultPath], alTerminar:)`: reindexa ya, sin esperar a la vigilancia.
  - `escriturasPropias: RecentWrites?`: lo que la vigilancia vea de ellas se reindexa, pero **no** llega a
    `onExternalChange`. `onExternalChange` queda solo para cambios de fuera.
- `NoteKindResolver.isTemplate(_:)`: las notas de `…/Sistemas/Plantillas/…` son `.note` aunque lleven `tls_type`
  (no cuentan como fichas ni como sistemas en el índice).
- `AreaReader.parse` lee la ficha de área v2 (SISTEMAS §2.3): `estado` de las propiedades manda sobre la línea
  `**Estado:**`; `ocupante`, `rol` y `convierte` rellenan lo que falte; `nombre` es el título si no hay `#`; la tabla
  `| Código | Sistema | Estado |` de `## Sistemas` se lee como lista de sistemas.

## TLSImport (público)

- `ConversorG2.planificar(origen:opciones:) throws -> PlanConversionG2`,
  `ConversorG2.convertir(origen:destino:opciones:) async throws -> InformeConversionG2`.
- `OpcionesConversionG2(clase: VaultClass = .copia, hoy: String? = nil)`; `PlanConversionG2` (`ficheros`,
  `informe`, `datos(_:)`); `InformeConversionG2: Codable` (`hashArbol`, `destino`, avisos y campos sin convertir);
  `ErrorConversionG2`.
- Garantías: nunca escribe encima (destino nuevo, carpeta temporal renombrada al final), rechaza iCloud antes de tocar
  el disco, nunca crea `clase: real`, no modifica el origen. «Destino dentro del origen» se comprueba con `realpath`
  en los dos lados (`/tmp` y `/private/tmp`, `/var` y `/private/var` son lo mismo).
- **Cambio de comportamiento:** `DemoCopier.copy` registra la copia nueva con
  `WritePolicy.escrituraInicial(para: .copia)` = `.permitida` (en F0, `.bloqueada`).

## TLSAgents (público; producto de librería en F4)

- Procesos: `ProcessSpec`, `ProcessOutput`, `LineDecision`, `ProcessError`, `ProcessRunner.run(_:onLine:)`
  (grupo de procesos propio; SIGTERM y SIGKILL a los `grace` segundos), `ProcessRunner.groupAlive(_:)`.
- Claude: `ClaudeVersion`, `ClaudeAuthStatus.parse`, `ClaudeInstallation`, `ClaudeLocator(home:shell:fallbackDirectories:)`
  (`verifiedVersion = 2.1.307`, `locate()`, `authStatus(…)`, `-ilc` para el PATH), `AgentEnvironment.minimal(…)`.
- Preflight: `ClaudeHelp(text:)`, `ClaudeSession {new, resume, ephemeral}`, `ClaudeRunOptions`,
  `ClaudeCommandLine.build(_:help:) throws -> {arguments, warnings}`, `PreflightError.flagsAusentes`.
- Sandbox: `SandboxProfileBuilder(home:deniedRoots:agentDirectory:runDirectory:socket:readOnly:)` (`build`, `write`,
  `claudeReadPaths`, `realPath`); permite DNS (`mDNSResponder`) y vuelve a negar la carpeta de la empresa al final.
- Stream: `AgentEvent`, `StreamJSONParser` (`consume`, `finish`, `events(fromLine:)`), `InitGuard(server:whitelist:mode:)`
  (`evaluate(_:) -> Verdict`; bloquea servidores, herramientas, complementos no de serie y `apiKeySource != none`).
- Ejecución: `FailureReason`, `RunState` (`from(result:)`, decide por `is_error`), `AgentPaths`, `MCPServerConfig`,
  `RunFiles`, `ClaudeProbe(claude:help:home:)` (`prepare`, `run`).

## tls-tool

- `convertir-g2 <origen> <destino> [--clase copia|demo] [--hoy AAAA-MM-DD] [--json]`.
- `renombrar <carpeta> <ruta> <nombre nuevo> [--aplicar] [--forzar] [--sin-alias] [--excluir <ruta>…] [--detalle N]`:
  sin `--aplicar` solo enseña la vista previa (cada fichero y cada enlace, antes y después); con `--aplicar` escribe
  con `CommandBus` y comprueba que no aparece ningún enlace roto nuevo (`SaludDeEnlaces`, antes y después).
- `deshacer <carpeta> [--ver]`: deshace el último plan de la app en esa carpeta (lee el diario del estado).
- Las dos órdenes que escriben solo aceptan copias y la demo (la entrada de `vaults.json` si está registrada; si no,
  `clase` de `.tls/config.yaml`; sin ella se trata como la carpeta real y se rechaza). El estado va a
  `TLS_APP_SUPPORT/<id>`.

## Pendiente para la interfaz (cuando haya diseño elegido)

- Al arrancar: `VaultRegistry().permitirEscrituraEnCopias()` (las copias de F0 se registraron `bloqueada`).
- Al abrir una copia o la demo: `VaultWriter.open` + `CommandBus` + `service.conectar(writer)`; enseñar
  `writer.lastRecovery`, `writer.conflicts.pendientes()` y `DuplicateDetector(…).scan()` como tarjetas.
- Modo solo lectura: `service.desconectar(writer)` y `writer.close()`.
- `AppModel.registerReadOnly` sigue registrando `bloqueada` (correcto para «Ver sin tocar»).
- «Nueva…» con `PlantillaRegistro.desde(tipo:)` + `PlantillaMotor.preparar`; renombrar desde Carpeta con
  `RefactorPreview.resumen`/`cambios`, `LinkRefactor.aplicar`, `avisoHecho` y Deshacer; pasar
  `writer.conflicts.pendientes()` en `Opciones.conflictos`; lo movido fuera de la app, con
  `arreglarMovimientoExterno`.
- Instalar el ejemplo (`Contents/Resources/Recursos/Ejemplos/Asesoria-Ribera`, con `.tls/`) en
  `~/The Last System/Empresas/` con un `id` nuevo.
- **Tipos de ficha (hallazgo 9 de fidelidad, sin hacer porque toca la interfaz):** la lectura de F0 trata como «Nota» 26
  de los 47 `tls_type` de las plantillas (agreement, background, brand, capture, closure, collaboration, connection,
  diagnosis, editorial_plan, import_report, incident, index, invoice, log, period, portal, procedure, proposal, quote,
  receipt, report, root_cause, routine_log, session_summary, strategy y welcome; en Ribera, 31 notas). Hace falta, a la
  vez: ampliar `NoteKind` (`Model.swift`), sus etiquetas e iconos (`TLSUI/Support/Presentation.swift`, switch
  exhaustivo) y subir `VaultIndex.schemaVersion` para que el índice se rehaga.
- `PlantillaError.yaExiste`: ofrecer «Completar la que hay» (`PlantillaMotor.aplicar`) en lugar de crear otra.
- Si una creación pierde la carrera con otra (`WriteResult.conflicto` / `cambioExterno` con «cambió fuera»), volver a
  preparar la nota con una foto nueva sin enseñar el error.

**Hecho en los cimientos de la interfaz (22/10, ver `docs/F1-INTERFAZ-CONTRATOS.md`):** `permitirEscrituraEnCopias` al
arrancar; escritor conectado en copias y en el ejemplo (`VaultSession.escribir` con Deshacer); recuperación,
conflictos, duplicados e iCloud como tarjetas en «Revisar»; modo solo lectura (`desconectar` + `close()`); los 47 tipos
de ficha con `VaultIndex.schemaVersion` = 2. Quedan para los roles de pantallas: «Nueva…» con plantillas y
`yaExiste`, renombrar desde Carpeta, instalar el ejemplo y volver a preparar una creación que pierde la carrera.

**Hecho en las fichas (22/10):** «+ Nuevo» ya enlazado desde cada ficha con `PlantillaMotor.preparar` (y
`TaskStore.crear` en las tareas), «Completar la que hay» con `PlantillaMotor.aplicar` ante `PlantillaError.yaExiste`, y
una creación que pierde la carrera (`destinoOcupado` o `cambioExterno`) se vuelve a preparar una vez con una foto nueva
sin enseñar el error. Renombrar desde la ficha (⋯ › Renombrar) con `LinkRefactor` y su vista previa. Relaciones en
`Sources/TLSCore/Relaciones/` (ver `docs/F1-INTERFAZ-CONTRATOS.md`, «Cambios pedidos»).

**Hecho en la integración de la interfaz (23/10):** todo lo de esta lista está en la app 0.2.0 (instalar el ejemplo,
«Nueva…» y renombrar desde Carpeta, lo movido fuera con `arreglarMovimientoExterno`, «Combinar» en Revisar). Cambios
en el núcleo que pidió la interfaz, cada uno con su prueba:
- `PlanCompiler.esVistaGuardada`: una persona (nunca un asistente) puede escribir `.tls/vistas/<base>.json` (un nivel,
  JSON legible). `.obsidian/` sigue sin escribirse (`EscrituraVistasTests`).
- `VaultWriter.undoLast`: deshacer la creación de un ajuste oculto lo retira a `Archivo/Ajustes de la app/…`
  (`componentesVisibles`); antes fallaba porque en `Archivo/` no puede haber carpetas ocultas.
- `VaultService.refreshCaches`: el `LinkResolver` conoce también los adjuntos por su nombre
  (`IndexBuilder.rutasDeFicheros`, sin abrir ni descargar nada). Solo se rehace cuando cambia algo del índice: un PDF
  nuevo suelto entra con el siguiente cambio de notas (mientras, el editor lo encuentra con `ResolutorAdjuntos`).
- `FormatoBase.cifra/euros/numero`: sin NaN ni infinitos (antes, `Int64(.nan)` cerraba la app).

## Revisión final (corrector, 22/10)

Aplicadas las dos revisiones de F1, con prueba de regresión para cada hallazgo:
- **Seguridad de datos (15 hallazgos):** `Tests/TLSCoreTests/RevisionSeguridad/RevisionSeguridadTests.swift`,
  `Tests/TLSImportTests/RevisionSeguridadCopiaTests.swift` y `Tests/TLSUITests/RevisionSeguridadUITests.swift` (sin
  `withKnownIssue`). Nuevo: `Formato/CodeFence.swift` (vallas de código de CommonMark en los 8 sitios que las miraban).
- **Fidelidad con Obsidian (hallazgos 1-8 y 10):** `Tests/TLSCoreTests/RevisionFidelidad/RevisionFidelidadTests.swift`
  y «Tampoco dentro del origen si una de las rutas se escribe con o sin «/private»» en `Conformidad/ConversorG2Tests`.
  El hallazgo 9 queda para la interfaz (arriba).
- Corregido sobre el parche de fidelidad: la regla «la mayor versión más uno» se aplica solo a nombres con «v» delante
  del número; aplicada a `{{fecha}}-seguimiento-{{orden}}` daba «Seguimiento 1» cada día.
- `AtomicFiles`: el temporal se borra también si falla el punto de control (las pruebas de cortes dejaban carpetas en
  `$TMPDIR`).

## Revisión final de la interfaz (corrector final, 23/10)

Cambios del núcleo que pidió la revisión de datos de la interfaz (detalle en `docs/F1-INTERFAZ-CONTRATOS.md` §13):
- `VaultLayout.isPrivate(_:)`: lo retirado a `Archivo/<ruta privada>` (y a `Archivo/Conflictos|Duplicados/…`) sigue
  siendo privado: no sale en ⌘O, ⌘K, Recientes ni vistas previas, y un asistente no puede escribirlo.
- `EdicionCelda`: `EdicionError.demasiadoGrande` (desde `FormatoBase.cifraMaxima`, 1e15), lo escrito se lee con
  `FormatoBase.numeroEscrito` («1.235» = 1235) y un CSV solo convierte a `true`/`false` los valores sí/no.
- `NotaIndiceBase.frase/cambiandoFrase`: listas, bloques de código, comentarios y HTML no son la frase.
- `AjustesBases.modulos(yaml:)`: la línea propia de un módulo manda sobre las listas.

## Cambios pedidos

- **integración → conformidad (hecho, 22/10):** `EjecutorVaultWriter` ejecuta «renombrar» con `LinkRefactor` como
  plan propio; el caso `escritor-renombrar-actualiza-enlaces` ya corre (11 casos golden).
- **integración → importación (hecho, 22/10):** `DemoCopier` registra las copias con escritura (ver arriba) y
  `DemoCopierTests` lo espera así.
- **corrector → escritor (hecho, 22/10):** `EscrituraWriterTests` espera que, después del primer arranque, una copia
  en solo lectura siga `bloqueada`.
- **corrector → funciones (hecho, 22/10):** `FormatoTests.nombreRepetido` y `RefactorTests.pendientesAmbiguosYFlojos`
  siguen la regla de Obsidian (desde fuera de las dos carpetas gana la ruta más corta; ambiguo solo con empate exacto).
- **corrector → conversor (hecho, 22/10):** `ConversorG2.rutaReal` y su prueba en `Tests/Conformidad`.
