# F0 · Contratos entre módulos

F0 = «Ver mi empresa»: **solo lectura** sobre una copia de trabajo. La especificación completa está en `docs/PLAN.md` (§3, §4.1, §4.7, §4.8 «Vigilancia» e «iCloud», §8 y §9 F0).

## Propiedad de ficheros durante la construcción en paralelo

| Módulo | Ficheros | Dueño |
|---|---|---|
| TLSCore | `Packages/TLSKit/Sources/TLSCore/**`, `Tests/TLSCoreTests/**` | núcleo |
| TLSImport + tls-tool | `Sources/TLSImport/**`, `Sources/tls-tool/**`, `Tests/TLSImportTests/**` | importación |
| TLSDesign + TLSUI | `Sources/TLSDesign/**`, `Sources/TLSUI/**`, `App/**` | interfaz |
| Build y DMG | `Makefile`, `scripts/**`, `README.md`, `docs/pruebas/**`, `docs/PROCEDENCIA.md`, `project.yml`, `Config/**` | build |

`Model.swift`, `VaultEntry.swift` y las firmas públicas de `VaultService` / `VaultRegistry` / `DemoCopier` son el contrato. Se pueden **ampliar** (añadir), no cambiar. Si hace falta cambiar una firma, se anota en la sección «Cambios pedidos» de este fichero.

## TLSCore (público)

- `VaultPath`, `LocalDate`: hechos.
- `AreaCode`, `AreaStatus`, `AreaSummary`, `SystemRef`, `PropertyValue`, `Property`, `NoteKind`, `NoteSummary`, `SearchHit`, `FolderEntry`, `NoteContent`, `IndexProgress`, `IndexStats`: `Model.swift`.
- `VaultEntry`, `VaultClass`, `WriteAccess`, `AppLocations`: `VaultEntry.swift`.
- `VaultRegistry`: `load()`, `upsert(_:)`, `remove(id:)`, `makeBookmark(for:)`, `resolveURL(_:)`.
- `VaultService(entry:root:)`: `open(progress:)`, `close()`, `onExternalChange`, `areas()`, `children(of:)`, `read(_:)`, `quickOpen(_:limit:)`, `search(_:limit:)`, `backlinks(to:)`, `resolveLink(_:from:)`, `requestDownload(_:)`, `summary(of:)`.

## TLSImport (público)

- `CopyOptions`, `CopyProgress`, `CopyReport`, `CopyError`, `DemoCopier.copy(from:into:options:progress:)`, `FileSystemAccess`, `LocalFileSystem`.
- Ampliaciones de F0 (solo añadidos; nada existente cambia):
  - `FileSystemAccess`: `isSymbolicLink(_:)`, `contents(of:)`, `modificationDate(_:)`, `setModificationDate(_:for:)`, con implementación por defecto.
  - `CopyReport.enlacesOmitidos` (los enlaces simbólicos no se siguen ni se copian).
  - `DemoCopier(fileSystem:appSupport:)`, `stateDirectory(for:)`, `reportFileName` («copia-informe.json»).
  - `CopyGuardError` (`proteccionICloud`, `destinoDentroDelOrigen`): errores previos a copiar que `CopyError` no recoge.
  - `Inventory.make(of:exclusiones:incluirArchivo:conHashes:fileSystem:progress:)`, `InventoryEntry`, `Inventory.diferencias(con:)`, `hashArbol`.
  - `ExclusionRules` (NFC, sin distinguir mayúsculas; poda antes de descender), `CopyConfig.yaml(...)` y `CopyConfig.peek(_:)` (`id`, `clase`, `origen`, `creada` y `privado` de `.tls/`).
    **Desde el 22/10 `ExclusionRules` vive en TLSCore** (misma API pública); TLSImport añade `forCopy`.
  - `ICloudProtection.protectCurrentProcess()` para herramientas de línea de órdenes.
- `VaultEntry.exclusionesCopia` y `CopyReport.exclusiones` llevan lo elegido por la persona, el `privado` de `.tls/` del origen y `Archivo` si no se copió (no las de `CopyOptions.siempre`).

## Garantías de F0 (criterios de aceptación del plan §9 F0)

1. La app no escribe nada en ninguna carpeta de empresa, salvo lo que crea `DemoCopier` en la copia nueva.
2. Una ruta excluida nunca se lista, se recorre, se lee ni se enlaza: tampoco escrita con otras mayúsculas
   (APFS no las distingue) ni a través de un enlace simbólico a mitad de ruta (`PathGuard`, con `realpath`).
3. Nada se descarga de iCloud al escanear o copiar (`setiopolicy_np`). Solo `requestDownload` al abrir una nota
   de texto; lo que el visor no muestra (PDF, vídeo…) nunca se descarga.
4. El índice es desechable: vive en `AppLocations.vaultState(id)/index.sqlite`, nunca dentro de la carpeta de la
   empresa ni en iCloud Drive. Si cambian las exclusiones o la estructura, se rehace desde cero (sin restos).
5. Lo que `.tls/` declara `privado` se lee siempre con el núcleo (Yams y plantillas `{finanzas}/…`): la copia lo
   deja fuera y «Ver sin tocar» no lo lista ni lo indexa. Si esos ajustes no se pueden leer, la copia no se hace.

## Cambios pedidos

- **interfaz → quien lleve `Package.swift` (no es firma de contrato):** añadir el target de pruebas de la interfaz.
  Los ficheros ya están en `Tests/TLSUITests/` (Swift Testing, 26 pruebas) y hoy no se compilan porque el target no existe:
  ```swift
  .testTarget(
      name: "TLSUITests",
      dependencies: ["TLSUI", "TLSDesign", "TLSCore", "TLSImport"]
  ),
  ```
  Comprobado en un paquete de prueba idéntico con ese target añadido: compilan y pasan.
  **Hecho (integración, 22/10):** target añadido en `Package.swift`; `swift test` ejecuta ya las pruebas de interfaz.
- **build → importación (CLI de `tls-tool`, no es firma de contrato):** `docs/pruebas/F0.md` y `scripts/conformidad.sh` usan
  `tls-tool inventario <ruta> [--excluir <ruta relativa>]...`. Pido: (1) que la opción se llame `--excluir` (repetible) y aplique la
  misma poda que `Inventory.make(of:exclusiones:)`; (2) salida en stdout **estable** (sin fecha ni duración), para que dos pasadas
  sobre una carpeta sin cambios den el mismo texto byte a byte; (3) que las últimas líneas resuman ficheros, «solo en iCloud»,
  excluidas y `hashArbol`. Si se elige otro nombre, avisad y ajusto la guía.
  **Resuelto (build, 21/10):** `Sources/tls-tool/Inventario.swift` ya cumple los tres puntos; la guía usa además `--json` para la copia.
  - **Hecho (importación):** `--excluir` repetible (también `--excluir a b`), misma poda que `Inventory.make`; stdout sin fecha ni
    duración; las 5 últimas líneas son «Ficheros: … · carpetas: … · enlaces: …», «Bytes: …», «Solo en iCloud: N»,
    «Rutas excluidas (no listadas): N» y «Hash del árbol: <sha256>». `--json` da el inventario completo; `--sin-hashes` lo acelera.
- **núcleo → todos (informativo; no cambia ninguna firma, solo añade):**
  - `VaultService(entry:root:options:)` con `VaultService.Options(privado:excluidas:stateDirectory:indexarArchivo:vigilar:)`.
    `init(entry:root:)` sigue igual (usa opciones por defecto). Lo privado se une a `privado` de `.tls/layout.json` y
    `.tls/config.yaml`; **nada privado está escrito en el código**. `excluidas` (más `entry.exclusionesCopia`) no se lista,
    no se recorre ni se lee. **Interfaz:** al abrir la carpeta real con «Ver sin tocar», pasad la carpeta que la persona
    declara privada en `excluidas` (o en `privado` si debe verse marcada).
  - `VaultService.layout` (`VaultLayout`) y `layoutAviso` (texto para la persona si `.tls/layout.json` no se pudo leer).
  - `onExternalChange` sigue siendo `var`; ahora está protegido por cerrojo. Se llama en la cola del índice.
  - `VaultRegistry.installationID()` (crea `instalacion.json` la primera vez). `resolveURL` devuelve `nil` si la carpeta ya no existe.
  - Tipos públicos reutilizables: `NoteDocument`, `Frontmatter`/`FrontmatterReader`, `CSVTable`, `LinkParser`/`ParsedLink`,
    `LinkResolver`, `VaultLayout`, `NoteKindResolver`, `AreaReader`, `UbiquityInspector` (`info`, `withoutMaterializing`,
    `requestDownload`), `FileInfo`, `VaultWatcher`, `TextDecoding`, `TextFolding`, `VaultServiceError`.
  - **build:** los ficheros portados llevan cabecera de procedencia; falta registrarlos en `docs/PROCEDENCIA.md`:
    `Formato/VaultLayout.swift` (de `layout.go`), `Formato/AreaReader.swift` (de `library.go`, `parseSystem`) y
    `Formato/LinkParser.swift` (de `databases.go`, `noteRefs`), todos de Manuel Trigo.
    **Hecho (integración, 22/10):** registrados en `docs/PROCEDENCIA.md`.
- **Integración (22/10, solo añadidos):**
  - `AppModel.registerReadOnly(url:privadas:)` (el parámetro tiene valor por defecto `[]`). «Ver sin tocar» hace
    ahora la pregunta obligatoria de carpetas privadas; lo elegido se guarda en `exclusionesCopia` de `vaults.json`
    (se suma a lo ya guardado, nunca se quita) y `VaultService` no lo lista, no lo recorre ni lo indexa.
  - `VaultIndex`: un índice con la versión de esquema actual pero sin todas sus tablas («no such table: meta»)
    se borra y se reconstruye solo, como uno de otra versión.

- **Corrector final (22/10, revisiones de privacidad, criterios y calidad).** Cambios de contrato:
  - **TLSCore (añadidos):** `ExclusionRules` se mueve aquí desde TLSImport (misma API; quien lo use necesita
    `import TLSCore`). `TextFolding.pathKey(_:)`. `VaultLayout.declaredPrivado(root:) throws`,
    `VaultLayout.avisoIlegible`, `VaultLayoutError`. `AppLocations.iCloudDrivePath` e `isInICloudDrive(_:)`.
    `VaultService.waitUntilIdle()`. `VaultServiceError.exclusionNoEncontrada(String)` y `.estadoNoPermitido(String)`.
  - **TLSCore (comportamiento):** `VaultLayout.isPrivate` y todas las exclusiones sin distinguir mayúsculas;
    `privado` admite una cadena sola y las plantillas se expanden con las carpetas de área reales;
    `read`/`children`/`resolveLink`/`requestDownload` comprueban la ruta real (`PathGuard`); `read` devuelve
    `.binary` sin pedir descarga si no es texto; en la carpeta real (`clase == .real`) lo `privado` de `.tls/` se
    excluye y una exclusión de la entrada que ya no existe hace fallar `open` (la interfaz vuelve a preguntar);
    `close()` para la apertura en curso (sin vigilancia huérfana); `onExternalChange([])` = revisar todo
    (reescaneo o cambio de `.tls/`); índice con `busy_timeout` de 10 s, `secure_delete` y WAL vaciado al cerrar.
    `TLS_APP_SUPPORT` y `TLS_EMPRESAS` se ignoran si apuntan a iCloud Drive.
  - **TLSImport (cambio de firma):** `ExclusionRules.forCopy(personales:privado:incluirArchivo:)` recibe
    `privado: [VaultPath]` (rutas literales, nunca patrones) en vez de `[String]`. Solo lo usaban TLSImport y sus pruebas.
  - **TLSImport (añadidos):** `CopyGuardError.privadoNoEncontrado(String)` y `.privadoIlegible`;
    `FileSystemAccess.trashItem(_:)` (con implementación por defecto: Papelera); `CopyConfig.Peek.origen` y `.creada`;
    `Inventory.make(of:exclusiones:incluirArchivo:conHashes:completo:fileSystem:progress:)`.
  - **TLSImport (comportamiento):** `privado` se lee con `VaultLayout` (no con un lector propio de YAML) y una ruta
    declarada que no existe para la copia; `CopyReport.exclusiones` (y `VaultEntry.exclusionesCopia`) son solo lo
    declarado que de verdad se podó, con el nombre en disco; una copia cancelada o con la verificación fallida va
    a la Papelera; `copia-informe.json` guarda `vaultID` en minúsculas.
  - **TLSUI (añadidos):** `AppModel.registerReadOnly(url:privadas:config:)` (`config` con valor por defecto) y
    `AppModel.replaceExclusion(id:missing:with:)`; `VaultSession.Phase.exclusionPerdida(String)`,
    `VaultSession.entry` pasa a `private(set) var`, `replaceMissingPrivate(_:with:using:)`, `retryDownload()`,
    `downloadGaveUp`; `NoteSnapshot.spans`; `MarkdownStyler.spans(forMarkdown:)` y
    `attributed(markdown:spans:)`; `MarkdownStyler.maxStyledLength` baja a 256 K.
  - **tls-tool:** `indexar --excluir <ruta>…` (y hereda las exclusiones de `vaults.json` si la carpeta está
    registrada); `inventario --completo` (mira también ocultos, `.DS_Store` y `Archivo/`; lo privado sigue fuera).

- **F1 (22/10):** la API nueva de F1 (escritura, enlaces, plantillas, tareas, Adoptar, conversor G2, asistentes,
  `tls-tool renombrar`/`deshacer`) y sus añadidos al contrato de F0 (`VaultService.conectar`/`desconectar`/`reindexar`/
  `escriturasPropias`, `NoteKindResolver.isTemplate`, `AreaReader` v2, `DemoCopier` con escritura) están en
  `docs/F1-CONTRATOS.md`. Ninguna firma de F0 cambia.
