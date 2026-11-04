# F2 · Contratos entre roles («Tareas y áreas»)

F2 = PLAN §9 F2 (8 criterios), con §6.2–§6.5 y §4.2–§4.7, el diseño aprobado (`docs/propuesta/DISENO-MOSAICO-V2.md`) y
las maquetas M2. Lo de antes sigue en `docs/F0-CONTRATOS.md`, `docs/F1-CONTRATOS.md` y `docs/F1-INTERFAZ-CONTRATOS.md`:
aquí solo se añade. Como siempre, las firmas se pueden **ampliar**, no cambiar; un cambio se pide en «Cambios pedidos»
(al final).

Reglas que no se rompen (resumen): toda escritura por `CommandBus` (`sesion.escribir`, persona; `Autor.sistema` solo
para reglas), nunca se borra y todo se deshace; la carpeta real solo se lee; lo privado no aparece en Hoy, Decisiones,
Tareas, áreas, bases, ⌘K, búsqueda ni miniaturas; nunca un 0 inventado («Sin dato», «Sin meta»); ninguna salida sin el
clic de una persona; sin Claude hasta F4; sin dependencias nuevas; textos en español llano (lint del glosario).

## 1. Propiedad de ficheros

Cada rol **solo** edita lo suyo. Si necesitas algo de otro, créalo en tus ficheros con una extensión o pídelo en
«Cambios pedidos». Si la compilación falla por ficheros de otro rol a medias, espera y vuelve a compilar; no los toques.
Compila y prueba con tu carpeta: `swift build --package-path Packages/TLSKit --scratch-path build/spm-f2-<rol> --build-tests`
y `swift test` con la misma. Cero avisos nuevos.

### 1.1 Fase de núcleo (en marcha a la vez)

| Rol | Ficheros |
|---|---|
| números | `Sources/TLSCore/Metricas/**`, `Sources/TLSCore/Recursos/Programa/**` (y su línea de recursos en `Package.swift`), sus pruebas |
| dominio | `Sources/TLSCore/Dominio/**`, sus pruebas |
| banco | `Sources/TLSCore/Finanzas/**`, sus pruebas |
| andamio | `Sources/TLSUI/Areas/**`, `Sources/TLSUI/Pantallas/{Hoy,Decisiones,Tareas}*` (huecos), `Sources/TLSUI/Navegacion/**`, `Sources/TLSUI/Shell/**`, `Sources/TLSCore/Indice/**` (texto de PDF), `Sources/TLSVisores/Miniaturas/**`, este documento y sus pruebas (`Tests/TLSUITests/Areas/*.swift`, `Tests/TLSCoreTests/Indice/**`, `Tests/TLSVisoresTests/Miniaturas/**`) |

### 1.2 Fase de pantallas (después, cuatro roles en paralelo)

| Rol | Ficheros | Pruebas |
|---|---|---|
| hoy-decisiones | `Sources/TLSUI/Pantallas/{Hoy,Decisiones}*` (hoy: `HoyPantalla.swift`, `DecisionesPantalla.swift` con `DecisionDetalle`), `Sources/TLSUI/Pantallas/Modulos/**` (incluye `ResumenDeArea.swift`, el Resumen de cada área) | `Tests/TLSUITests/{Hoy,Decisiones,Modulos}/**` |
| tareas | `Sources/TLSUI/Pantallas/Tareas*` y `Pantallas/Tareas*/**` (hoy: `TareasPantalla.swift`), `Sources/TLSUI/Tareas/**` (`TareaDetalle.swift`, `NuevaTareaHoja.swift`) | `Tests/TLSUITests/Tareas/**` |
| areas-a | `Sources/TLSUI/Areas/Operacion/{Direccion,Ventas,Entrega}*`, `Sources/TLSUI/Areas/Entrega/**` (y `Areas/Direccion/**`, `Areas/Ventas/**` si hacen falta) | `Tests/TLSUITests/Areas/{Direccion,Ventas,Entrega}/**` |
| areas-b | `Sources/TLSUI/Areas/Operacion/{Finanzas,Marca,Equipo}*`, `Sources/TLSUI/Areas/Finanzas/**` (`BancoPantalla.swift`), `Sources/TLSUI/Areas/Marca/**`, `Sources/TLSUI/Areas/Equipo/**` | `Tests/TLSUITests/Areas/{Finanzas,Marca,Equipo}/**` |

En la fase de pantallas **nadie** toca: el resto de `Sources/TLSUI/Areas/*.swift` y `Areas/Componentes/**` (el andamio),
`Navegacion/**`, `Shell/**`, `State/**`, `BarraLateral/**`, `TLSDesign`, `TLSCore` ni `Package.swift`. Lo que haga falta
ahí se pide abajo. Los targets de pruebas ya existen: basta con crear la subcarpeta.

## 2. Huecos: el `init` es contrato

Todos compilan y enseñan algo verdadero (lo de F1 o qué habrá, sin cifras). Empiezan con `// HUECO (andamio F2) · rol …`
y dicen qué falta según el PLAN. **Se rehace el cuerpo, no la firma.**

| Dónde se usa | Tipo (fichero) | `init` | Rol |
|---|---|---|---|
| `.hoy` | `HoyPantalla` (`Pantallas/HoyPantalla.swift`, la de F1) | `init(sesion: VaultSession)` · conservar `static saludo(_:calendario:)` y `fechaLarga(_:)` (las usan las pruebas) | hoy-decisiones |
| `.decisiones` | `DecisionesPantalla` (`Pantallas/DecisionesPantalla.swift`) | `init(sesion: VaultSession)` | hoy-decisiones |
| `.decision(id)` | `DecisionDetalle` (mismo fichero) | `init(id: String, sesion: VaultSession)` | hoy-decisiones |
| Resumen de un área | `ResumenDeArea` (`Pantallas/Modulos/ResumenDeArea.swift`) | `init(contexto: ContextoArea, sesion: VaultSession)` | hoy-decisiones |
| `.tareas` | `TareasPantalla` (`Pantallas/TareasPantalla.swift`) | `init(sesion: VaultSession)` | tareas |
| `.tarea(ruta)` | `TareaDetalle` (`Tareas/TareaDetalle.swift`; hoy enseña la ficha de F1) | `init(ruta: VaultPath, sesion: VaultSession)` | tareas |
| ⌘N | `NuevaTareaHoja` (`Tareas/NuevaTareaHoja.swift`; ya crea con `TaskStore`) | `init(contexto: Destino, sesion: VaultSession)` (hoja de la pestaña; cierra con `@Environment(\.dismiss)`) | tareas |
| Operación de cada área | `DireccionOperacion`, `VentasOperacion`, `EntregaOperacion` (`Areas/Operacion/`) | `init(contexto: ContextoArea, sesion: VaultSession)` | areas-a |
| Operación de cada área | `FinanzasOperacion`, `MarcaOperacion`, `EquipoOperacion` (`Areas/Operacion/`) | `init(contexto: ContextoArea, sesion: VaultSession)` | areas-b |
| `.banco(cuenta)` | `BancoPantalla` (`Areas/Finanzas/BancoPantalla.swift`) | `init(cuenta: VaultPath?, sesion: VaultSession)` | areas-b |

Las pantallas de Operación se pintan **dentro** del andamio (bajo las pestañas, en su `ContenedorPantalla`): no ponen
cabecera ni destacado propios (el destacado del área es el número clave; como mucho uno por pantalla). Si necesitan
desplazamiento propio (un tablero ancho), `ScrollView(.horizontal)` dentro de su vista.

## 3. Rutas y atajos nuevos

```swift
case tarea(VaultPath)          // detalle de una tarea → TareaDetalle
case decision(String)          // una decisión → DecisionDetalle; id libre («conflicto:…», «ruta:…»)
case banco(VaultPath? = nil)   // Banco de Finanzas → BancoPantalla; nil = todas las cuentas
```

- `Destino.decision(de: ruta)` y `destino.rutaDeDecision` para las decisiones que son una nota (pregunta de un
  asistente, borrador por aprobar, tarea `tipo: decision`). `identidad`, `ruta`, `moviendo(de:a:)` (renombrar y mover
  actualizan migas e historial), `puedeSerRaiz` (`.tarea` y `.decision` no; `.banco` sí) y `simbolo` ya las conocen;
  `sesion.nombre(de:)` las nombra («Banco · Cuenta corriente…», el título de la tarea o de la nota de la decisión).
- **Tareas como ficha:** `Destino.para` (y `sesion.destino(para:)`) sigue abriendo una tarea como `.ficha(ruta)` para no
  romper F1 (`RecorridoF1Tests` espera `.ficha(tarea)` en las migas). Cuando `TareaDetalle` esté listo, el rol de tareas
  **puede** cambiar en `Navegacion/Destino.swift` la línea de `para(_:tipo:esCarpeta:)` (`tipo == .task` → `.tarea(ruta)`)
  y la línea 95 de `Tests/TLSUITests/Integracion/RecorridoF1Tests.swift` (`.ficha(tarea)` → `.tarea(tarea)`). Es la
  única excepción a la propiedad de §1.2; anótalo en «Cambios pedidos».
- **Atajos** (menú Ir y Archivo): ⌘1 Hoy · ⌘2 Decisiones · ⌘3 Tareas · ⌘4–⌘9 las seis áreas (ya estaban) y **⌘N
  «Nueva tarea…»** (`HojaVentana.nuevaTarea`; desactivado en solo lectura). Dentro de una base, su propio ⌘N sigue
  creando una ficha de esa base (la vista gana al menú).
- `NuevaTareaHoja.areaDe(_:sesion:)`: el área por defecto según la pantalla (un área, su carpeta; Banco, Finanzas). Desde
  la ficha de un proyecto, la tarea va a `Proyectos/<slug>/Tareas/`.

## 4. Cómo navegar, leer y escribir (lo de F1, más lo de F2)

- Navegar: `@Environment(\.navegar)` y `navegar(.tarea(r))`, `navegar(.banco(nil), modo: .entrar)`… (F1 §3). En un
  área, `nav?.cambiarPestana("Control")` cambia de pestaña sin paso de historial. Lo que cada pestaña quiera recordar
  (sección, filtros), en `nav?.actualizarRecuerdo(de: .area(code)) { $0.extra["…"] = … }` (clave propia, p. ej.
  `"ventas.vista"`; `"soloRol"` es del andamio).
- Leer: la foto compartida de la empresa es `AlmacenRelaciones.de(sesion)` (`await actualizar()`, `foto`, `grafo`,
  `hoy`), rehecha con `sesion.revision` y soltada al cerrar la empresa. **Incluye lo privado**: filtrar con
  `sesion.esPrivado(_:)` o `foto.layout.isPrivate(_:)`. El índice (`sesion.resumen(de:)`, `sesion.buscar`) ya no lo trae.
- Escribir: `try await sesion.escribir(.comando, aviso:, deshacer:)` o `sesion.escribir(plan:)` (F1 §5), siempre como la
  persona (`sesion.autor`). Ninguna pantalla confirma un cobro, pasa a Ganada ni emite sola: lo hace un clic.
  **Desde la integración**, con escritor, también pasa por el motor del dominio (eventos y reglas, sin invariantes) y
  su Deshacer quita la cadena entera (§12).
- **Escribir a través del dominio** (lo que toca estados de oportunidades y proyectos, fichas con invariantes o
  `Decisiones.md`; lo pide el rol de dominio): `try await sesion.escribirConDominio(.comando, aviso:, deshacer:)` o
  `escribirConDominio(plan:…)` (`Shell/DominioEmpresa.swift`). Pasa por `MotorDeDominio` (invariantes → `CommandBus` →
  eventos → reglas como sistema), con el mismo aviso y Deshacer que `escribir`. Un bloqueo (VEN-07, ENT-01, precio) lanza
  `DominioError.bloqueado(resultado)` sin escribir y deja el aviso; la pantalla enseña `resultado.mensaje` y sus
  `alternativas` («Dejarla en Aceptada»). Para preguntar antes de soltar: `DominioEmpresa.motor(de: sesion)?.comprobar(…)`.
  El motor es uno por empresa con escritor (`nil` en solo lectura) y al crearse termina lo pendiente
  (`procesarPendientes()`).
- En solo lectura, los controles salen desactivados con su motivo (`ModeloArea.motivoSoloLectura` o
  `sesion.modoEscritura`).

## 5. El andamio de las áreas (`Sources/TLSUI/Areas`)

`AreaScaffold(area:pestana:sesion:)` es la pantalla de `.area(code, pestana:)`:
- **Cabecera azul noche:** «N · Área», «Convierte X en Y», estado (`FaseArea`), Rol, «La lleva» (o «Sin ocupante»),
  Etapa (si se sabe), la pregunta fija y el ritmo del área (`RhythmBadge`, el del número más atrasado); a la derecha,
  «Pedir a <asistente>» (desactivado: «Llega con los asistentes») y «Ver solo lo de este rol» (→ `contexto.soloRol`).
- **Destacado violeta:** `HeroNumber` con el número clave (`numero_clave` de `Área.md`, si no el primero de `numeros:`
  del rol, si no el primero del área en `Metas.md`). Sin meta decidida, «Fija la meta antes de ver el dato» y «Fijar la
  meta» (lleva a Control con el editor abierto).
- **Pestañas:** Resumen (`ResumenDeArea`) · Operación (`OperacionDeArea` → los seis huecos) · Control (`ControlArea`) ·
  Sistemas y activos (`SistemasYActivos`). Reposo: solo Resumen con «Activar» (avisa si otra área se activó hace menos
  de 30 días: `activada:` de su `Área.md`). Preparada: «Los asistentes aún no trabajan aquí». Etapas 1–2 sin ninguna meta
  decidida: Control dice «Medir esto llega en la etapa 3».

Tipos (valores `Sendable`, en `DatosArea.swift`):
- `ContextoArea` (lo que reciben Resumen y Operación): `area`, `carpeta`, `titulo`, `fase`, `etapa`, `rol`, `ocupante`,
  `soloRol`, `hoy`, `control: [FilaControl]` y `numero(_ codigo)`.
- `DatosArea` (todo el andamio): lo anterior y `convierte`, `pregunta`, `asistente`, `numeroClave`, `filaClave`, `metas`
  (ruta), `sistemas`, `activosSueltos`, `activacionReciente`, `ritmo`, `hayMetas`, `controlSustituido`, `pestanas`.
- `FilaControl` (una fila de `Metas.md` con su `LecturaNumero`): `meta`/`alerta` tal cual (`nil` = vacía), `metaDecidida`,
  `tieneMeta`, `sinMetaElegida` (celda «Sin meta»), `valorVisible`, `textoValor` («Sin dato», el valor u «Oculto hasta
  fijar la meta»), `textoMeta`, `textoAlerta`, `ritmo`, `etiquetaAccesible`.
- `LecturaNumero` (`valor`, `texto`, `ritmo: RitmoNumero`, `fuente`, `estimado`), `RitmoNumero` (En ritmo · Atención ·
  En alerta · Sin meta · Sin dato; `deArea(_:)`), `FaseArea`, `PestanaArea`.
- `SistemaDeArea` (los del catálogo del área, aunque falten, y los propios): `estado: EstadoSistema` (Falta · A medias ·
  Montado · Funciona sin ti), `ficha`, `numeroClave` (solo si `Metas.md` lo mide), `etapa`, `deSerie`, `funciones:
  [FuncionDeSistema]` (de la tabla `## Pasos` de su ficha: `modo: ModoFuncion` en lenguaje llano; lo que sale fuera,
  `sensible` y bloqueado en «Siempre con tu OK»), `activos`, `plantillas` (de la biblioteca), `revisado`, `sinTi`.
- `CatalogoSistemas` (los 19 de SISTEMAS §2.5, el asistente de cada área y el prefijo de sus códigos).

Lectura y escritura:
- `LectorArea(foto:hoy:proveedor:registro:).leer(_ area) -> DatosArea`: puro, fuera del hilo principal; nunca enseña
  lo privado ni lo archivado. `filasDeMetas()` da todas las filas de `Metas.md`.
- `ModeloArea(area:sesion:)` (`@Observable`, una por pantalla): `cargar()` con cada `sesion.revision`,
  `guardarMeta(_:meta:alerta:deshacer:)` (**solo** las celdas Meta y Alerta de esa fila, `.cambiarCeldas`; meta vacía =
  «Sin meta»), `activar(deshacer:)` (`estado: activa` y `activada: <hoy>` en `Área.md`), `editando`, `errorGuardado`.
- **Números:** `ProveedorNumerosArea.numeros(de:codigos:contexto:) -> NumerosDeArea` (`lecturas`, `etapa`).
  `ProveedoresArea.numeros` es `NumerosDelNucleo` (el del rol de números: `KPIEvaluador` para valor, ritmo y fuente —sin
  dato, su motivo como fuente— y `EtapaCalculador` para la etapa). Las pantallas que quieran más (gráfica de caja,
  cuello, objetivos) usan directamente `Sources/TLSCore/Metricas` (sección del rol de números).
- Componentes del andamio (solo TLSUI): `HeroNumber(fila:)`, `RhythmBadge(_:palabra:sobreColor:)` y
  `RhythmBadge(area:)`, `ModoPastilla(modo:)`, `AvisoEnLinea(_:estado:)`, `HuecoOperacion`.

## 6. R1 en F2: texto de los PDF y miniaturas

- **Búsqueda:** `VaultIndex.schemaVersion` = 3 (un índice anterior se rehace solo). Tablas `pdfs` (ruta, área, tamaño,
  fecha, `dataless`, estado: pendiente · hecho · sin_texto · sin_descargar · grande · error) y `pdfs_fts`. El escaneo
  (`IndexBuilder`) solo apunta los PDF **no privados** y fuera de `Archivo/`; `ColaTextoPDF` los lee después, en su cola
  de prioridad baja, de 4 en 4, con PDFKit (`ExtractorPDFKit`: 300 páginas y 300.000 caracteres como mucho; más de 80 MB,
  no), **solo si están en el Mac** (lectura dentro de `UbiquityInspector.withoutMaterializing`) y comprobando otra vez
  que la ruta no es privada justo antes de leer. El texto solo vive en `index.sqlite` (fuera de la carpeta). Si iCloud
  se lleva un PDF ya leído, su texto se conserva; si cambia, se vuelve a leer. `VaultService.search` (y
  `sesion.buscar`) mezcla notas y PDF por relevancia: un PDF sale como `SearchHit` con `kind: .other`, título = nombre
  del fichero y fragmento con «‹…›»; `sesion.destino(para:)` lo abre en el visor. Un PDF **no** es una nota: no sale en
  ⌘O ni en `resumen(de:)`. Cerrar la empresa para la cola y espera al fichero en curso.
- **Miniaturas:** `CacheMiniaturas(directorio:carpetaEmpresa:maximo:)` (TLSVisores; se niega dentro de la carpeta o en
  iCloud Drive) guarda PNG en `<estado de la empresa>/miniaturas/` con clave ruta + tamaño + fecha + página + lado (si el
  fichero cambia, no se enseña la vieja); poda a 2.000. `MiniaturaConCache(url:tipo:pagina:lado:cache:acceso:)` la
  pinta (icono del tipo mientras tanto o si está en iCloud; nunca descarga). En TLSUI: `MiniaturaDeRuta(ruta:sesion:pagina:lado:)`
  (**nunca pinta una ruta privada**) y `MiniaturasEmpresa.cache(de: sesion)`.

## 7. API del núcleo de F2

Cada rol de núcleo añade aquí su sección (qué expone y cómo se usa desde las pantallas). El andamio no la escribe.
**Aviso del andamio (23/10, 11:02):** este fichero se escribió entero a esa hora; si alguien había puesto ya aquí su
sección, puede haberse perdido: el borrador del dominio (`scratchpad/f2-dominio.md`, 10:58) está copiado tal cual en
§7.2. Números y banco: comprobad que lo vuestro está y, si no, volved a ponerlo.

### 7.1 Números (`Sources/TLSCore/Metricas`)

#### TLSCore · números (rol números: `Sources/TLSCore/Metricas/**`, `Sources/TLSCore/Recursos/Programa/**`, `Tests/TLSCoreTests/Metricas/**`)

Números clave, ritmo, etapa, cuello, salud, chequeos, tarjetas y agenda (PLAN §2.4, §6.2, §6.5 «Control», §9 F2). Port
de PROG `core/{tarjetas,tiempo,salud,madurez,consultoria,areas,lecturas}.js` y `core/sql/{02,03,05,08,10,13,14}` (ver
`docs/PROCEDENCIA.md`). Todo es **determinista** (sin asistentes) y con **reloj inyectable**: `Reloj` (en la demo, `hoy:`
de `.tls/config.yaml`; zona `agenda.zona`, por defecto Europe/Madrid). Solo lee, salvo `MetasEscritor` (persona, por
`CommandBus`, solo las celdas Meta y Alerta). Lo privado, lo retirado a `Archivo/` y las plantillas no entran en nada.
Sin fuente → `MedidaKPI.sinDato(motivo)` («Sin dato»); sin meta → `EstadoKPI.sinMeta` («Sin meta»). Un 0 solo sale si hay
fichas o filas de las que contar y la cuenta da 0 (Ribera a 5/10: 0 € ganados en octubre); lo que aún no existía a
`hoy` (fichas creadas después, movimientos posteriores) no cuenta.

- **Todo de una vez (lo que usan Hoy y las áreas)** — `PanelMetricas.calcular(snapshot:reloj:catalogo:eventos:estados:historial:)`
  o `PanelMetricas(foto:metas:catalogo:eventos:estados:historial:)`. Da `hoy`, `foto`, `metas`, `evaluador`, `kpis`
  (`[ValorKPI]`, las filas de `Metas.md` en su orden; sin `Metas.md`, las 21 del catálogo), `objetivos` (`[RitmoObjetivo]`),
  `ritmoAreas` (`[RitmoArea]`), `ritmoEmpresa`, `etapas` (`[EtapaArea]`), `etapaEmpresa`, `chequeos`
  (`[ResultadoChequeo]`, ordenados), `salud` (`[SenalSalud]`), `mapa` (`MapaMadurez`), `semana` (`SemanaAgenda`), `mazo`
  (`Mazo`), `foco` (`Tarjeta`, **siempre exactamente una**), `alertas` (`[AlertaHoy]`: **vacía = la sección Alertas no
  existe**; números en `mal` con meta y alerta escritas y reglas duras rotas, con su área), `hayRojo`, `decisionesAbiertas`,
  `frase(decisiones:)` («2 cosas piden tu decisión. Hoy tienes 3,5 h de 4.»; pasad `bandeja.pendientes` si la cuenta es la
  de la bandeja del dominio), `lineaMika(hora:)` («Revisé a las 8:45: nada en rojo.» / «… 5 cosas en rojo (Finanzas,
  Marca y Ventas).»; sábado y domingo «Los fines de semana no reviso…»), `control(area)`, `ritmo(area)`, `etapa(area)`,
  `salud(area)`. Rehacerlo con cada `sesion.revision` (Ribera: milisegundos), fuera del hilo principal.
- **Estándar** — `CatalogoPrograma.deSerie` (`cargado`; vacío si faltan los recursos y entonces lo que depende de él dice
  «Sin dato»), `cargar(carpeta:)`, `capacidades: [CapacidadStd]` (78: `codigo`, `area`, `modulo`, `nombre`, `nivel`
  esencial|recomendable|opcional, `ejecutorRecomendado`), `sistemas: [SistemaStd]` (24, `capacidades`, `desdeEtapa`,
  `pregunta`, `claves`), `etapas: [EtapaStd]` (`queToca`, `senal`), `areas`, `roles`, `modulos`, `rutinas`,
  `kpis: [KPIDefinicion]` (29: los 21 de Ribera y 8 de la propuesta v2; `unidad` n|%|€|meses|h|USD, `sentido`
  mas|menos|rango, `periodo` ahora|mes|trimestre|30d|90d, `acumulable`, `calculable`, `calculo`, `fuentes`, `origen`),
  `kpi(_)`, `recuentoRibera` (21). `RecursosPrograma.carpeta`. `Ejecutor` (humano · agente · automatización · regla fija:
  `init?(leyendo:)` acepta H/IA/A/S, `esAutomatico`, `siguiente`, `etiqueta`). `RangoFechas` (`mes(de:)`,
  `trimestre(de:)`, `diasEntre`, `contiene`, `dias`), `PeriodoKPI.rango(hoy:)`, `SentidoKPI(leyendo:)`.
- **`Metas.md`** — `MetasDocumento.leer(snapshot)` (`nil` si no está o es privado) / `init(texto:ruta:)`: `filas: [FilaMeta]`
  (`codigo`, `indicador`, `meta`/`alerta`: `Umbral`, `porQue`), `comoSeMide` (sentido y periodo de «## Cómo se mide»;
  el sentido de ahí manda sobre el del catálogo), `fila(_)`, `codigos`, `tieneTabla`, `ruta(layout:)`. `Umbral(texto:)`:
  `numero` (lee «80 %», «1000 €», «1.000 €», «2,5 meses»; «Todos» o «Por debajo de 3» no tienen cifra = sin fijar),
  `maximo` («3–6»), `fijado`. **Escribir:** `MetasEscritor.fijar(codigo:meta:alerta:en:catalogo:bus:autor:)` (solo
  `Autor.persona`, si no `MetasError.soloPersonas`; cifra con la unidad del catálogo, «4 meses», «80 %», «6000 €»; vacío
  = sin umbral) y `MetasEscritor.comando(_:codigo:meta:alerta:)` → `.cambiarCeldas` con **solo** Meta y Alerta (una
  línea cambia; deshacer deja los mismos bytes). `MetasError` (`sinMetas`, `codigoDesconocido`, `valorNoValido`,
  `soloPersonas`).
- **Foto** — `FotoMetricas(snapshot:hoy:)`: `oportunidades`, `proyectos` (con `objetivoRuta` y `sinObjetivo`),
  `objetivos`, `tareas` (`TareaMedida`: la `Tarea` de F1 con `estimacionH`, `dedicadasH`, `abierta`, `esDecision`),
  `contenidos`, `conversaciones`, `roles` (`ocupante`, `declaraOcupante`), `contactos`, `borradores`, `reuniones`, `rutinas`,
  `estadoAreas`, `facturas` (emitidas con `vence`/`base` de su ficha), `gastos`, `pagos`, `cuentas`
  (`saldo(a:)`: el último del banco; si no, inicial + movimientos; si no, `nil`), `usos` y `ejecuciones` (bitácora),
  `decisiones` (fechas de `Decisiones.md`), `registros` (qué CSV existen), `config` (`ConfigMetricas`: `topeHorasDia`,
  `topeTarjetasDia`, `zona`, `capacidades`, `titular`, `esTitular`). Tipos anidados (`FotoMetricas.Oportunidad`…) para no
  chocar con los del dominio.
- **Números** — `KPIEvaluador(foto:catalogo:metas:)`: `todos()`, `delArea(_)`, `evaluar(codigo) -> ValorKPI`,
  `medir(_:rango:) -> (MedidaKPI, fuente)` (en el rango que se pida: así se mide un objetivo en su periodo),
  `cajaDisponible()` (`Caja`: `total` `nil` si falta alguna cuenta, con su motivo), `salidaMensual()` (media de los 3
  últimos meses **cubiertos enteros** por los movimientos, sin traspasos), `traspasos()`, `pendiente(factura)` (cobros
  confirmados hasta hoy), `formatear(_:unidad:)`, `estado(_:meta:alerta:sentido:)` (llegar a la alerta ya es alerta; a la
  meta, meta). `ValorKPI`: `codigo`, `indicador`, `area`, `unidad`, `sentido`, `periodo`, `rango`, `medida`, `meta`,
  `alerta`, `estado` (Bien · Atención · Mal · Sin meta · Sin dato), `ritmo: RitmoKPI` (`estado: EstadoRitmo`, `pct`,
  `esperado`: los que se suman en el mes o el trimestre, frente a la parte que ya pasó; los de nivel, por su estado),
  `fuente` («Sale de 7 oportunidades abiertas»), `calculo`, `enMetas`, `textoValor`, `textoMeta` («Sin meta»),
  `textoAlerta`, `metaFijada`. Calculables: DIR-APR, DIR-DEC, DIR-DEC14, DIR-OBJ, ENT-ACTIVE, ENT-ONTIME, ENT-OVERDUE,
  EQU-COST, EQU-ROLES, FIN-AR, FIN-CASH, FIN-MARGIN, FIN-RUNWAY, FIN-UNREC, MAR-PUB, MAR-QCONV, VEN-CONV, VEN-FCST,
  VEN-PIPE, VEN-STALE, VEN-STALE7, VEN-WON y (integración) ENT-INC, de `FotoMetricas.incidencias` (los `Incidencias.md`
  de los proyectos de entrega; sin ninguno, «Sin dato»). «Sin dato» siempre (aún no hay fuente): EQU-HEALTH, BUZ-PEND,
  FIN-FISCAL, ENT-ARR48, VEN-REF, EQU-RUT.
- **Ritmo** — `RitmoCalculador(evaluador:)`: `objetivos(excepto:)` (`RitmoObjetivo`: `estado`, `real`, `esperado`,
  `diasTotal`, `diasPasados`, `diasRestantes`, `pct`, `avancePct`, `falta`, `motivo`), `ritmo(de:)`, `empresa()`
  (`RitmoEmpresa`: media capada a 100), `areas(kpis:)` / `area(of:kpis:objetivos:)` (`RitmoArea`: `estado` En ritmo ·
  Atención · En alerta · Sin meta · Sin dato · En reposo, `marca` = el código más atrasado, `frase`, `pct`). `EstadoRitmo`
  (adelantado · en ritmo · atención · en riesgo · crítico · sin dato · sin meta; `retraso`, `medible`, `enTrayectoria`).
  Un objetivo necesita `meta`, `desde`, `hasta` y `medido_por`; `acumulado: true` = esperado proporcional al tiempo.
- **Etapa** — `EtapaCalculador(foto:catalogo:)`: `areas()`, `area(_)` (`EtapaArea`: `etapa`, `cobertura`, `pctAuto`,
  `manuales`, `tieneDueno`, `progreso` (3,4 = a medio camino de la 3 a la 4), `faltanEtapas`, `sistemas:
  [EstadoSistemaStd]` (montado · a medias · falta, `haceFalta`), `paso` y `porque`), `empresa(_)` (`EtapaEmpresa`: la del
  área más floja, `porque`, `actual`, `siguiente`). Solo cuenta lo **declarado** en `.tls/config.yaml`
  (`capacidades: {FIN-05: {declarada: si, ejecutor: IA, desde: 2026-10-21}}`; un `desde` posterior a hoy aún no cuenta).
  Dueño = rol humano del área con `ocupante` que no eres tú (`titular:` en config; «Manu», «yo» y «titular» siempre).
- **Chequeos** — `Chequeo(foto:metas:semana:)`: `chequeos()` (los 7 de DI2: `CHQ-1` tareas sin proyecto · `CHQ-2` vencidas
  (grave) · `CHQ-3` proyectos sin nada pendiente · `CHQ-4` pendientes con fechas · `CHQ-5` oportunidades sin valor o sin
  responsable · `CHQ-6` cobro previsto a 60 días (`info`) · `CHQ-7` carga por encima del tope), `comprobaciones()` (las 15 de
  Programa: DIR-03 (atención, acciones «Colgar de un objetivo» / «Seguir sin objetivo»; `sin_objetivo: true` lo calla),
  DIR-03b, VEN-03, VEN-01, VEN-08, VEN-11, ENT-01, ENT-03, ENT-07, FIN-01, FIN-06, ORG-01, ORG-02, EQU-01, DIR-09),
  `todos()`, `hayRojo()`, `ordenar(_)`. `ResultadoChequeo`: `codigo`, `familia`, `nivel` (grave · flojo · info), `area`,
  `titulo`, `regla`, `arreglo`, `casos` (`ruta`, `detalle`), `acciones`, `n`, `esRojo`.
- **Salud y cuello** — `SaludCalculador(evaluador:objetivos:kpis:etapas:chequeos:).senales()` → `[SenalSalud]` (`area`,
  `dimension` Resultado · Ritmo · Capacidad · Automatizaciones · Datos · Flujo, `estado` bien · atención · mal, `detalle`,
  `porFaltaDeDato`). `CuelloCalculador(evaluador:etapas:empresa:salud:ritmos:chequeos:)`: `presiones()`
  (`PresionArea`: presión = (100 − ritmo) + mal × 25 + atención × 10 + a mano × 3, `motivo`), `cuello()`, `mapa()` →
  `MapaMadurez` (`etapas`, `filas`, `presiones`, `cuello`, `empresa`, `camino: [TramoCamino]` con `porque`/`entrada`/`salida`,
  `textoCuello` «El cuello es 2 · Ventas: …», `veredicto`, `marcada(area, etapa:)` para la celda del mapa 6×6).
- **Tarjetas** — `TarjetaBuilder(evaluador:objetivos:presiones:etapas:estados:historial:catalogo:)`: `mazo(nivelMax:)` →
  `Mazo` (`tarjetas` vivas por puntos, `mostradas` = todas las rojas + `avisos.tope_tarjetas_dia` (5) de las demás,
  `fueraDelTope`, `mazos` por área, `foco`, `rojas`, `impactoTotal`), `foco()`, `generar()`. `Tarjeta`: las cinco preguntas
  (`quePasa`, `porQueImporta`, `queHago` = el botón, `siNo`, `recomendacion`), `boton: BotonTarjeta` (`etiqueta`,
  `accion: AccionTarjeta`: abrir, marcarHecha, prepararMensaje, prepararReclamacion, decidirPlan, replantearPlazo,
  meterEnEmbudo, fijarUmbral, verArea, bajarDeEscalon, convertirEnRegla, verSemana; «preparar» deja un borrador, nunca
  envía), `acciones`, `tipo`, `nivel`, `area`, `factores`, `puntos`, `prioridad` (normal · atención · crítico · riesgo
  para la empresa; `esRoja`), `patron`, `contexto`, `id` determinista. Lo que decide la persona se guarda **fuera de la
  carpeta** y se pasa: `EstadoTarjeta` (`pospuestaHasta`, `descartada`, `resuelta`) y `DecisionTarjeta` (patrón y acción;
  3 iguales dan la tarjeta CRITERIO «Convertir en regla»). Sin nada vivo, el foco es «Nada urgente: reparte la semana».
- **Agenda** — `Agenda(foto:eventos:).semana(de:)` → `SemanaAgenda` (`lunes`…domingo, `dias: [DiaAgenda]`, `tope`,
  `atrasadas`, `titulo`, `totalHoras`, `capacidad`, `diasPasados`, `diaDeHoy`, `fraseHoy`). `DiaAgenda`: `tareas`
  planificadas, `vencimientos`, `reuniones`, `rutinas` (semanales por su día, mensuales por el del mes), `eventos`
  (`EventoAgenda`, los inyecta quien lea el Calendario), `cobros` previstos, `horas`, `sinEstimar` (sin estimación no se
  inventan horas), `tope` (0 en sábado y domingo: ENT-04), `pasaDelTope`, `aviso`, `textoCarga` («3,5 h de 4»).
  `Agenda.laborable(_)`.
- **Lectura y análisis de un área** — `LecturaArea.de(area, panel:)` (`titular`, `texto`, `recomendacion`, `firma`: la
  lectura del consultor sin asistente). `AnalisisArea.cifras(area, periodo:panel:)` → `[CifraArea]` (`nombre`, `medida`,
  `unidad`, `pie`, `textoValor`) con `PeriodoArea` (hoy · semana · mes · trimestre · todo).

Ribera a 19/10/2026 (calculado a mano en `Tests/TLSCoreTests/Metricas/`): DIR-APR 0 · DIR-DEC 2 · DIR-OBJ 67 % (atención)
· ENT-* y EQU-* sin dato · FIN-AR 0 € · FIN-CASH 26.664,65 € · FIN-MARGIN −413 % (mal: octubre factura 150 € y gasta
770 €) · FIN-RUNWAY 7,9 meses · FIN-UNREC 1 · MAR-PUB 3 · MAR-QCONV 2 (mal) · VEN-CONV 70 % · VEN-FCST 325,50 € · VEN-PIPE
870 € · VEN-STALE 1 · VEN-WON 660 € (mal). Etapa 1 en las seis áreas (nada declarado). Cuello: Ventas (presión 177). Foco:
«6.000 € de ventas cobradas al mes: 53 % del ritmo» (43,4 puntos). 5 alertas (FIN-MARGIN, MAR-QCONV, VEN-WON, VEN-03,
VEN-01).

### 7.2 Dominio (`Sources/TLSCore/Dominio`)

<!-- Texto del rol de dominio (su borrador del 23/10, 10:58), puesto aquí tal cual por el andamio. -->

#### TLSCore · dominio (rol dominio: `Sources/TLSCore/Dominio/**`, `Tests/TLSCoreTests/Dominio/**`)

Invariantes, eventos, outbox, reglas, `Decisiones.md`, bandeja de Decisiones y expediente de empresa (PLAN §4.3, §4.4,
§4.7, §5.2; SISTEMAS §3.3–3.4; port de PROG `core/reglas.js` y `core/expediente.js`, ver `docs/PROCEDENCIA.md`).
Nada de aquí escribe por su cuenta: todo plan va por `CommandBus`.

- **Lectura** — `LecturaDominio(snapshot:reloj:)`: `fichas`, `ficha(_:)`, `ficha(id:)`, `fichas(_ tipo:)`, `oportunidades`,
  `proyectos`, `objetivos`, `facturas`, `pagos: [FilaPago]`, `emitidas: [FilaEmitida]`, `config: ConfigDominio`, `hoy`,
  `relacion(_:_:)` (lee también `*_id`), `que(apuntan:por:tipo:)`, `oportunidad(de: FilaPago)` (por `proyecto_id` o por
  `documento_id` → factura → `oportunidad`), `factura(numero:)`, `cobrosConfirmados(de:)`, `proyectosDeEntrega(de:)`,
  `precioDeOferta(_:desde:)`, `esDeEntrega(_:ruta:)`, `estadoOportunidad(_:)` / `estadoProyecto(_:)` (nombres heredados:
  Ganado, Borrador, En progreso, Completado…). Tipos: `FichaDominio` (`texto`, `uid`, `estado`, `fecha`, `centimos`,
  `clave`), `FilaPago` (`esCobroConfirmado`), `FilaEmitida`, `ConfigDominio` (`modos` de `capacidades`, `topeTarjetasDia`
  de `avisos.tope_tarjetas_dia`, `leer(yaml:)`), `ModoCapacidad` (`off|manual|asistido|supervisado|autonomo`,
  `esDePersona`), `PrecioDeOferta` (`centimos` o `minimo`/`maximo`, `admite`, `texto`), `Euros` (`texto(15000)` =
  «150,00 €», `escrito(15000)` = `150.00`). Lo privado se marca (`privada`) y no sale en listas, tarjetas ni avisos.
- **Invariantes** — `Invariantes(lectura:)` / `(snapshot:reloj:)`; `comprobar(_ CambioPropuesto, autor:) ->
  ResultadoInvariante` con `CambioPropuesto` = `.propiedades(ruta, poner:, quitar:)`, `.crear(ruta, texto:)`, `.plan(WritePlan)`
  (sin autor, el del plan). `ResultadoInvariante`: `veredicto` (`permitido|atencion|bloqueado`), `puedeGuardar`, `bloqueos`,
  `atenciones`, `mensaje`, `ajustes` y `corregir(_ plan)` / `corregir(_ poner:en:)` (ENT-04). `AvisoInvariante` (`codigo`:
  `VEN-07`, `ENT-01`, `PRECIO`, `DIR-03`, `ENT-04`; `nivel`: `informativo|atencion|bloqueo`; `mensaje`; `alternativas`).
  `AlternativaInvariante.Accion`: `.poner(ruta, props)`, `.elegirObjetivo(ruta, opciones:)`, `.abrir(ruta)`. Además
  `atenciones()` (DIR-03 y ENT-01 vigentes, sin privados), `colgar(_:de:)` (enlace al objetivo y quita `sin_objetivo`),
  `precioDeOferta(para:)`.
  - VEN-07: Ganada solo con un cobro de `pagos.csv` (`direccion: cobro`, `verificacion: confirmado`) que va a esa
    oportunidad, o confirmado por una persona en el mismo plan. Si no: bloqueo «Ganada necesita un cobro confirmado por una
    persona. …» con «Dejarla en Aceptada». Un asistente, nunca (ni con cobro).
  - ENT-01: proyecto de entrega (`clase: entrega` o, sin clase, en Entrega) sin oportunidad o con una oportunidad que ya
    tiene otro → bloqueo (con «Abrir «…»»). Solo se mira al crear o al tocar `oportunidad`/`clase`. Crear uno para una
    oportunidad sin cobro: atención (se guarda).
  - Precio: `precio_congelado` (al ponerlo o al cambiar `oferta_version`) tiene que ser el de la versión de la oferta o,
    sin versión, el del servicio; un servicio «a medida» admite su rango `precio_min`–`precio_max`. Si no: bloqueo con
    «Usar 150,00 € de la Oferta».
  - DIR-03: proyecto interno En curso sin `objetivo` ni `sin_objetivo: true`, en una carpeta con objetivos abiertos →
    atención (se guarda) con «Colgar de un objetivo» / «Seguir sin objetivo» (`sin_objetivo: true`, **propiedad nueva**).
  - ENT-04: `planificada` (cualquier ficha), `inicio`/`fin` (proyectos) y `siguiente_fecha` (oportunidades) en sábado o
    domingo pasan al lunes (ajuste automático y aviso informativo). `vence` nunca se toca.
- **Eventos** — `TipoEvento` (contacto.creado, empresa.creada, conversacion.cualificada, oportunidad.aceptada|ganada|perdida,
  cobro.confirmado, factura.emitida, proyecto.creado, proyecto.cerrado, extracto.importado, decision.registrada),
  `EventoDominio` (clave única `<tipo>:<id de la entidad>`, `carga`, `autor`, `profundidad`, `plan`), `CambioAplicado(ruta,
  antes, despues)`, `EventDeriver(layout:).derivar(_:autor:plan:profundidad:)` (puro). `cobro.confirmado` solo si la fila la
  escribe una persona. Nada de lo retirado, las plantillas, lo privado ni lo importado (`fecha_corte`) dispara eventos.
- **Estado** — `EstadoDominio(directory:)` = `<estado de la carpeta>/estado.sqlite` (el `stateDirectory` del escritor;
  no desechable). Migración `dominio-1`: tablas `outbox` (clave única) y `reglas_aplicadas` (clave única). `encolar` (`false`
  si ya estaba), `pendientes`, `marcar`, `eventos`, `evento(_:)`, `yaAplicada`, `apuntar`, `reglasAplicadas`, `cerrar`.
  Otras fases añaden sus tablas con migraciones propias, sin tocar estas.
- **Reglas** — `Regla(id:evento:capacidad:nombre:clave:paraPersona:preparar:)`, `ContextoRegla`, `ResultadoRegla`
  (`.nada(motivo)` | `.plan(plan, resumen:)`), `ReglasDeSerie.todas` (11), `GuardaDeReglas.comprobar(_:lectura:)`.
  De serie: contacto.creado → tarea «Preparar diagnóstico de …» (VEN-04); conversacion.cualificada → empresa y contacto
  enlazados a la conversación (MAR-07); cobro.confirmado → Ganada y proyecto de entrega, **una vez por oportunidad**
  (VEN-07); oportunidad.aceptada u oportunidad.ganada → factura y contrato en borrador si no los hay (FIN-02, FIN-10; misma
  clave en los dos eventos, SISTEMAS §3.4.6); oportunidad.ganada → su proyecto si falta y hay cobro (ENT-01);
  proyecto.creado → tareas del plan de entrega en días laborables, numeradas seguidas en un solo plan (ENT-02);
  proyecto.cerrado → testimonio y caso de éxito como Idea en Marca (ENT-11, MAR-05).
- **Motor** — `MotorDeDominio(bus:opciones:)` (actor; `Opciones(persona:profundidadMaxima:reglas:reloj:)`, por defecto
  «Manu», 3, las de serie y el reloj de la carpeta). `ejecutar(_ plan)` / `ejecutar(_ comando, autor:)` →
  `ResultadoDominio` (`escritura`, `invariantes`, `eventos`, `reglas: [EjecucionRegla]`); lanza
  `DominioError.bloqueado(ResultadoInvariante)` sin escribir nada. `comprobar(_:autor:)`, `lectura()`,
  `setModoImportacion(_:)`, `procesarPendientes()`, `registrar(_ cambios:autor:plan:)`, `estado`. Las reglas escriben como
  `Autor.sistema`; cadena de 3 pasos como mucho (lo del cuarto queda `omitido`); en modo importación todo queda `omitido`;
  si la función está en `off`/`manual`, la regla deja una tarea para la persona (`EjecucionRegla.Resultado.tareaParaPersona`).
- **Decisiones.md** — `RegistroDecisiones.leer(_:)` (`lineas`, `linea(id:)`, `vigentes`), `ruta(_ layout)`,
  `anadir(_ NuevaDecision, en:autor:sustituye:id:) -> (plan, id)` (en `## <año>` si el registro las usa; si no hay registro,
  lo crea con la plantilla), `sustituir(_ idVieja, por:en:autor:id:)` (la vieja solo gana « (sustituida)»; la nueva lleva
  `"sustituye"`), `marcarSinMarcador(en:autor:)` (`"origen":"texto"`), `textoDeLinea`, `marcador`. `LineaDecision`
  (`id`, `fecha`, `decision`, `porque`, `area`, `origen`, `sustituida`, `marcador`, `numeroDeLinea`), `NuevaDecision`,
  `DecisionError`. Solo se añade: fuera de la línea nueva y de la marca, ningún byte cambia.
- **Bandeja de Decisiones** — `BandejaDeDecisiones.consultar(_ lectura, conflictos:persona:)` y `consultar(_:registro:persona:)`
  (con `writer.conflicts`) → `tarjetas`, `visibles`, `alResumen`, `grupos` (Para aprobar · Preguntas · Propuestas de mejora ·
  Archivos en conflicto), `resumenPorTipo`, `pendientes` (insignia), `rojas`. `TarjetaDecision` (`tipo`, `prioridad`
  `roja|alta|normal`, `motivo`, `titulo`, `problema`, `opciones: [OpcionDecision]` (como mucho 3, con la recomendada),
  `recomendada`, `porque`, `ruta`, `conflicto`, `area`, `responsable`, `creada`, `vence`). Roja: vencida, vence hoy o 14 días
  sin decidir (DIR-DEC14). Presupuesto: las rojas siempre; del resto, `tope_tarjetas_dia` por día de creación; lo demás, al
  resumen semanal.
- **Expediente** — `Expediente.de(_ empresa, en:)` → `contactos`, `oportunidades`, `proyectos`, `reuniones`, `facturas`,
  `cobros`, `tareas`, `conversaciones`, `linea: [HechoDeExpediente]`, `alertas: [AlertaDeExpediente]`,
  `numeros: NumerosDeExpediente` (céntimos; `nil` = «Sin dato», nunca 0 inventado).

#### Cambios pedidos (dominio → otros roles)

- **banco:** confirmar una conciliación (movimiento `conciliado` + fila de `pagos.csv` con `verificacion: confirmado`) debe
  escribirse con `MotorDeDominio.ejecutar(plan)` como persona: así sale `cobro.confirmado` y, de ahí, Ganada y proyecto. Si
  se escribe con el `CommandBus` directamente, llamar después a `motor.registrar([CambioAplicado(ruta: pagos, antes:,
  despues:)], autor:)`. `LegacyMovementsImporter` y cualquier importación: `setModoImportacion(true)` durante la escritura.
  El extracto original en `…/Bancos/<cuenta>/Extractos/` da `extracto.importado`.
- **andamio / interfaz:** un `MotorDeDominio` por sesión con escritor (mismo `CommandBus`); `procesarPendientes()` al abrir;
  escribir por `motor.ejecutar` lo que toca el dominio (estados de oportunidades y proyectos, propiedades de fichas,
  `Decisiones.md`); al soltar en Ganada, `motor.comprobar(.propiedades(…))` y, si `bloqueado`, enseñar `mensaje` y la
  alternativa «Dejarla en Aceptada»; `DominioError.bloqueado` lleva el mismo resultado. DIR-03: `Invariantes.atenciones()`
  con sus dos botones. Decisiones: `BandejaDeDecisiones.consultar(lectura, registro: writer.conflicts, persona:)`; la
  insignia es `pendientes`.
- **interfaz (F1):** `GrafoRelaciones.cobroConfirmado` acepta una factura «Cobrada» o un recibo; VEN-07 es más estricto
  (`pagos.csv`). Usar `Invariantes`/`LecturaDominio.cobrosConfirmados` para el tablero del CRM.
- **números:** los chequeos y el `TarjetaBuilder` pueden leer `Invariantes.atenciones()` (DIR-03, ENT-01) y la bandeja
  (`rojas`, DIR-DEC14) en vez de recalcularlos.
- **diccionario (SISTEMAS §1.5):** propiedad nueva `sin_objetivo: true` en proyectos («Seguir sin objetivo»).
- **pendiente de decidir:** cada regla escribe su propio plan como sistema; «Deshacer» deshace el último plan (puede ser de
  una regla). Falta «deshacer la cadena entera» y las propuestas de regla en modo `asistido` (necesitan guardar el plan en
  `estado.sqlite`: `WriteOp` aún no es `Codable`).

### 7.3 Banco (`Sources/TLSCore/Finanzas`)

#### TLSCore · banco (rol banco: `Sources/TLSCore/Finanzas/**`, `Tests/TLSCoreTests/Finanzas/**`)

Extractos, conciliación, caja y trimestre (PLAN §4.6, §7.3, §6.5; SISTEMAS FI1–FI3). Nada de aquí escribe: cada
operación devuelve un `WritePlan` (todo o nada, un solo Deshacer) que la pantalla ejecuta. Importes en **céntimos**
(`Int`); sin dato = `nil` («Sin dato»), nunca 0. Lo privado y lo retirado a `Archivo/` no entran (ni cuentas, ni
registros, ni la ruta de un documento privado). Port de PROG `core/fiscal.js` y `core/sql/11-fiscal.sql` (ver
`docs/PROCEDENCIA.md`); lo del banco y la conciliación, solo desde PLAN §4.6 (FORK `finance.go` no se abrió).

- **Registros** — `RegistrosFinanzas(snapshot:)`: `carpeta`, `cuentas: [CuentaBancaria]`, `movimientos: [MovimientoBanco]`
  (todas las cuentas, por fecha), `emitidas`/`recibidas: [FacturaRegistro]`, `pagos: [PagoRegistro]`, `avisos` (filas
  ilegibles, cuentas sin ficha o con el mismo `id`, en castellano), `emitidasCSV`/`recibidasCSV`/`pagosCSV`,
  `cuenta(id:)`, `movimientos(de:)`, `factura(id:)`, `confirmado(de:)` y `pendiente(de:)` (total − pagos confirmados;
  `nil` sin total), `rutaRelativa(_:)` (como la escribe `evidencia`), `resolverDocumento`, cabeceras de serie
  (`cabeceraEmitidas|Recibidas|Pagos|Movimientos`). `FacturaRegistro` completa base, IVA, retención, `vence` y
  `oportunidad` con la ficha de la factura (`documento` → `tls_type: invoice`); `sinRevisar` = `estado_revision: pendiente`.
  `CuentaBancaria` (`id` de `Cuenta.md`, `formato`, `saldoInicial`, `movimientosCSV`, `extractos`), `EstadoConciliacion`
  (`pendiente|propuesta|conciliado|ignorado`, `abierto`), `PagoRegistro.confirmado`. `DineroExacto`: `centimos(_:)`,
  `centimos(_:decimal:)`, `csv` (`-663.00`), `coma` (`-663,00`), `euros` (`-1.234,56 €`).
- **Extractos** — `BankStatementParser.leer(_ data:formato:)` → `ExtractoLeido` (`filas: [FilaExtracto]` con `fila`,
  `fecha`, `fechaValor`, `concepto`, `importe` con el signo del banco, `saldo`; `formato`; `formatoAdivinado`; `avisos`).
  `;` y coma decimal o `,`/tabulador y punto; cabeceras del banco (sinónimos) o las de `formato_extracto`; cargo y abono
  separados; BOM, `\r\n`, UTF-16 y Windows-1252; líneas encima de la tabla y totales al final (aviso). `ErrorExtracto`.
  `FormatoExtracto` (`separador`, `decimal`, `formatoFecha`, `columnas`; `leer(deFicha:)` de `Cuenta.md`; `propiedad`
  para `cambiarPropiedades`).
- **Importar** — `ImportadorExtracto(snapshot:reloj:).vistaPrevia(datos, nombre:, cuenta:, adivinarFormato:)` →
  `VistaPreviaExtracto`
  (`filas: [FilaConHuella]` con `huella`, `movimientoID`, `yaImportada`, `repetidaEnElFichero`; `nuevas`,
  `yaImportadas`, `resumen` «29 movimientos · 0 nuevos · 29 ya importados», `original`, `lote`, `guardaFormato`,
  `plan(autor:)` (`nil` con 0 nuevos), `evento(autor:)`). Contrato: `ImportadorExtracto.huella(cuentaID:fecha:importe:
  concepto:saldo:repeticion:)` = SHA-256 de `"<cuenta_id>|<AAAA-MM-DD>|<céntimos>|<concepto en minúsculas>|<saldo o vacío>"`
  y `|#n` desde la segunda fila idéntica sin saldo; `movimientoID` = `MOV-<12>`. El original va a
  `Extractos/AAAA-MM-DD <nombre>.csv` (con « (2)» si el nombre está ocupado con otros bytes; no se vuelve a guardar si ya
  está). Hasta 50 filas nuevas, una `guardarFila` por fila; con más, una sola `anadirLinea` (ver «Cambios pedidos»).
  **Revisión final (§13):** ahora siempre una sola `WriteOp.insertCSVRows`, que nunca pisa ni repite un `id`.
  Naturaleza nueva solo por el signo (`ingreso`/`gasto`), `estado_conciliacion: pendiente`; clasificar es del Contable.
- **Conciliar** — `ConciliationMatcher(registros:).proponer()` → `[PropuestaConciliacion]` (`movimiento`, `cuenta`,
  `factura`, `pendiente`, `coincidencia` `.numeroFactura|.contraparte`, `dias`, `empates`, `exacta`, `motivo` en
  castellano). Importe exacto contra lo pendiente; número de factura (más peso) o primera palabra de la contraparte;
  movimiento ≥ factura − 3 días; gana la más próxima; una factura por movimiento y un movimiento por factura.
  `Conciliador(registros:reloj:)` / `(snapshot:reloj:)`: `propuestas`, `confirmar(_:autor:)`, `confirmar(_ lote:autor:)`,
  `confirmarLasExactas(autor:)` → `ConfirmacionConciliacion` (`plan`, `pagos`, `eventos`, `resumen`). **Solo una persona**:
  con `.sistema` o `.agente` lanza `ErrorConciliacion.soloUnaPersona`. Escribe `conciliado` + `documento_id` + `pago_id` +
  motivo en el movimiento y la fila `PAG-AAAAMMDD-NNN` (fecha del movimiento; cobro si entra dinero, pago si sale;
  `metodo` solo si el concepto lo dice; `evidencia = Registros/Bancos/<c>/movimientos.csv#MOV-…`;
  `verificacion = confirmado`). `planProponer(_:autor:)` (deja `propuesta`; lo puede hacer un asistente) y
  `planIgnorar(_:motivo:autor:)`.
- **Eventos** — `EventoFinanzas` (`tipo` `extracto.importado|cobro.confirmado`, `clave`, `fecha`, `autor`, `datos`) con la
  **misma clave** que `EventoDominio` (`cobro.confirmado:PAG-…`, `extracto.importado:ruta:<ruta en minúsculas>`): darlos
  también al dominio no los repite. `cobro.confirmado` lleva `documento_id`, `pago_id`, `movimiento_id`, `importe`,
  `fecha_cobro`, `tercero`, `factura` (ruta de la ficha) y `oportunidad` (el enlace tal cual).
- **Caja** — `Tesoreria(registros:hoy:)` / `(snapshot:reloj:)`: `saldo: SaldoCaja` (`total` `nil` si falta alguna cuenta,
  `conocido`, `estimado`, `fecha`, `cuentas: [SaldoCuenta]` con `fuente` `banco|estimado|desconocido`), `saldo(de:)`,
  `runway: Runway` (`meses` con un decimal, `salidaMedia` redondeada al céntimo, `mesesUsados`, `estimado`, `motivo` si no
  hay dato: media de los 3 últimos meses que los movimientos del banco **cubren enteros** —integración: como
  `KPIEvaluador`—, sin traspasos entre cuentas propias), `traspasos`, `serie(_ RangoCaja)` →
  `[PuntoCaja]` (un punto por día hasta hoy; `saldo` `nil` = la gráfica se corta; `estimado`), `RangoCaja` (1S · 1M · 3M ·
  1A · Todo, `titulo`), `cobrosPendientes`/`cobrosVencidos: [CobroPendiente]` (vencidas primero; `diasVencida`),
  `totalVencido` (FIN-AR), `sinConciliar` (FIN-UNREC), `sinRevisar`. Con Ribera: caja 26.664,65 €, 7,9 meses, 0 € vencido,
  1 sin conciliar (lo mismo que `KPIEvaluador`).
- **Trimestre** — `PeriodoTrimestre` (`desde`, `hasta`, `precierre`, `domiciliacion`, `plazo` —el T4, 30 de enero—,
  `titulo` «T3 2026», `anterior`, `siguiente`, `aPresentar(hoy:)`). `TrimestreFiscal(registros:hoy:forma:)`:
  `resumen(_:)` → `ResumenTrimestre` (`ingresos`/`gastos: TotalesLibro`, `modelo303|130|111|115: EstimacionModelo`,
  `diasHastaPlazo`, `faltan`), `modelo303(_:)` (IVA repercutido − soportado; tipos fiscales de 11-fiscal.sql si la fila
  trae `tipo_fiscal`), `modelo130(_:)` (solo autónomos; acumulado del año), `modelo111(_:)` (retenciones a profesionales;
  las nóminas del banco sin su retención dejan «Sin dato»), `modelo115(_:)` (alquileres). `EstimacionModelo` (`aplica`
  `.si|.no(motivo)|.sinDato(motivo)`, `resultado` `nil` si falta algo, `parcial`, `lineas`, `faltan`, `notas`).
  `FormaJuridica.deCarpeta(_:)`: `fiscal: {forma: autonomo|sociedad}` de `.tls/config.yaml` o la letra del NIF de
  `facturacion` (Ribera: sociedad, sin 130). Todo es **Estimado**: lo presenta la gestoría.
- **Paquete para la gestoría** — `PreparadorPaquete(registros:reloj:)` / `(snapshot:reloj:)`: `documentos(_:)` (originales
  de `Fiscal/AAAA/Tn/{Ingresos,Gastos}` leídos por su nombre con `LectorFiscal`, y las fichas de factura) y `preparar(_:)` →
  `PaqueteGestoria` (`carpeta` `Fiscal/AAAA/Tn/Modelos/Paquete gestoría/`, `ficheros` índice + `libro-ingresos.csv`,
  `libro-gastos.csv`, `movimientos.csv`, `diferencias.csv` con «;» y coma decimal, `documentos`, `diferencias`, `listo`,
  `yaExiste`, `resumen`, `plan(autor:)` que solo crea lo que no hay; si el índice existe no se toca nada). **No envía
  nada.** `LectorFiscal` (port de `fiscal.js`): `fecha`, `importe`, `tipoFiscal`, `categoria`, `leerIngreso`, `leerGasto`,
  `reglas`.
- **Heredados** — `LegacyMovementsImporter(snapshot:)`: `ficheros` (`Registros/importar/*.csv`, sin privados),
  `preparar()` → `PreparacionHeredada` (`filas: [FilaHeredada]` con `destino` `emitida|recibida|pago`, `registro`, `pago`,
  `yaCargada`; `nuevas`, `avisos`, `resumen`, `columnasQueNoCaben`, `plan(autor:)`). Filas con `estado_revision:
  pendiente` y `fuente: importacion`; los pagos (solo si el fichero los da por cobrados o pagados, y los gastos sin factura
  como la cuota de autónomos o los impuestos) con `verificacion` vacía y `evidencia = Registros/importar/<fichero>#fila-N`.
  Nunca toca `movimientos.csv` ni confirma. Volver a cargar da 0 nuevos (clave de contenido). Si el fichero trae
  `importe` e `IVA` sin `total` ni `base`, el importe es la base (exportación de Notion).

## 8. Pantallas · Operación de Dirección, Ventas y Entrega (rol areas-a)

Ficheros: `Sources/TLSUI/Areas/Operacion/{Direccion,Ventas,Entrega}Operacion.swift` (los huecos, misma firma),
`Sources/TLSUI/Areas/{Direccion,Ventas,Entrega}/**`, `Sources/TLSCore/AreasA/**` (carpeta propia, lo imprescindible: ver
«Cambios pedidos») y `Tests/TLSUITests/Areas/{Direccion,Ventas,Entrega}/**`. Todo se escribe como la persona de la
sesión, con Deshacer; lo que toca estados de oportunidades y proyectos, por `sesion.escribirConDominio`.

- **Común** (`Areas/Direccion/OperacionComun.swift`) — `CargaOperacion<Datos>(sesion:calcular:)` (`@Observable`: foto
  compartida de `AlmacenRelaciones` → cálculo fuera del hilo principal con cada `sesion.revision`; `datos`, `foto`,
  `motivoSoloLectura`), `FranjaCifras`/`CifraOperacion` (cifras pequeñas de arriba desde `ValorKPI`: valor, «Sin meta»,
  estado con palabra y fuente; **no** es el destacado), `BloqueOperacion`, `SeccionesOperacion` (pestañas en cápsula sin
  ⌃1–⌃9; recuerdo en `nav.recuerdo(de: .area(a)).extra[clave]`), `OperacionComun` (`ritmo(EstadoRitmo)`, `estado(EstadoKPI)`,
  `nombre(enlace)`, `lunes(de:)`, `laborable(_:paso:)`). Claves de recuerdo: `direccion.vista`, `ventas.vista`,
  `entrega.vista`, `entrega.expediente` (ruta del expediente abierto), `entrega.pestana`, `entrega.portal` (`cliente`).
- **Cronograma** (`Areas/Direccion/Cronograma*.swift`) — `Cronograma.internos(proyectos:objetivos:ritmos:atenciones:hoy:)`
  (internos de las 6 áreas, ni de entrega, ni cerrados ni archivados, por objetivo; «Sin objetivo» al final, `gris`; la
  atención DIR-03 la pone `Invariantes.atenciones()`), `Cronograma.deEntrega(_:hoy:)`, `mover(inicio:fin:dias:)` (fin de
  semana → lunes), `cambiarFin`, `moverUnDia`, `comando(_:inicio:fin:)` (solo `inicio` y `fin`). `CronogramaVista` (Gantt
  en `Canvas`: arrastrar la barra mueve, el borde derecho cambia el fin; menú, ← → y ⇧← ⇧→ y acciones de VoiceOver).
- **Dirección** — `DatosDireccion.calcular(foto:hoy:)` (`PanelMetricas` + `Invariantes`: cronograma, objetivos con ritmo,
  mapa 6×6, cronología de `Decisiones.md`, DIR-DEC14 y DIR-OBJ, `PlanCuello`). `PlanCuello.proponer(mapa:etapas:hoy:)`
  (3 acciones del cuello, de los sistemas que hacen falta, y «Volver a diagnosticar»; una por lunes) y
  `tareas(_:persona:autor:)`. `AccionesDireccion`: `mover`, `colgar(_:de:sesion:deshacer:)` (DIR-03 «Colgar de un
  objetivo»), `seguirSinObjetivo` (`sin_objetivo: true`), `registrar(_ NuevaDecision…)` (`RegistroDecisiones.anadir`),
  `crearPlan(_:semanas:…)` (con tu OK, todas en un plan: `LoteDeTareas`), `fotoActual`, `conflicto`, `texto`.
- **Ventas** — `DatosVentas.calcular(foto:hoy:)`: `TableroCRM.de(_:hoy:soloResponsable:)` (`ColumnaCRM`: `numero`, `total`
  —`nil` = «Sin dato»—, `conversion` = % que pasa a la siguiente; en Ganada, ganadas sobre cerradas; `TarjetaCRM.quieta`
  = VEN-STALE7, «quieta 9 d»), `TableroCRM.soltar(_:en:invariantes:autor:)` → `ResultadoSoltar` (`.escribir(comando)` que
  cambia solo `estado`, `.bloqueado(mensaje:alternativa:)` con «Dejarla en Aceptada», `.nada`).
  `SeguimientoPropuesta.de(lectura:tareas:hoy:)` (oportunidades en Propuesta con su propuesta enviada: `dias`, `toca`
  7/14/21/30 si no hay ya una tarea «Seguimiento día N · …», `proximo`, `preparados`, `borrador(_:hoy:)` determinista,
  `nuevaTarea`). `DirectorioVentas`. `AccionesVentas`: `mover` (pregunta antes a `Invariantes`; si bloquea, no escribe),
  `aplicar(_ AlternativaCRM…)`, `prepararSeguimiento` (tarea con el borrador; **nunca envía**).
- **Entrega** — `DatosEntrega.calcular(foto:hoy:ahora:)` (la hora de ahora con el día de la carpeta): `ExpedienteEntrega`
  (proyecto de entrega con `portal`, `incidencias`, `tareas`, `materiales`, `textoSesiones`, `riesgo(hoy:ahora:zona:)`),
  cronograma, `carga` (`DiaCarga`, de lunes a viernes: tareas de Entrega con estimación y sesiones agendadas frente al tope)
  y cifras ENT-ONTIME (núcleo) y **ENT-INC contada aquí** (abiertas fuera de plazo; «Sin dato» si no hay ningún registro).
  `RevisionViernes.de(_:)`. `AccionesEntrega`: `cambiarSesion` (solo la celda Estado de esa fila del Viaje) y
  `nuevaIncidencia` (fila INC-NNN con fecha y hora, responsable la persona; sin `Incidencias.md`, lo crea con la plantilla
  «registro-de-incidencias» y la fila dentro; sube el contador `incidencia`). Vistas: `ListaExpedientes`,
  `ExpedienteDetalle` (Viaje · Tareas · Portal · Incidencias · Materiales), `PortalClienteVista` (solo pinta
  `PortalCliente`), `FilaIncidencia`, `NuevaIncidenciaHoja`, `CargaEntregaVista`, `RevisionViernesVista`.
- **TLSCore · `Sources/TLSCore/AreasA/`** (público):
  - `LoteDeTareas.preparar(_:snapshot:reloj:autor:descripcion:)` — puerta pública de `TareasEnLote` (dominio): varias
    tareas en un plan, números seguidos.
  - `PortalDocumento.leer(_:ruta:)` — `## Viaje` (`SesionViaje`: `codigo`, `nombre`, `celdaSesion`, `estado: EstadoSesion`
    Pendiente · Programada · Kit listo · Hecha · No incluida, `fecha`, `resumen`, `notaInterna`), `tareasCliente`
    (`TareaDelCliente`), `documentos`, `dudas`, `hechas`, `incluidas`, `proxima(hoy:)`, `comandoEstado(_:a:)`,
    `tablaViaje`. `PortalCliente(portal:incidencias:)` — la vista del cliente **sin** campos de nota interna,
    responsable, resolución, correo ni kit («Kit listo» → Programada; documentos del kit fuera; `limpiar` quita correos y
    frases del kit); `textoCompleto`.
  - `RegistroIncidencias.leer(_:ruta:zona:)` (`IncidenciaRegistrada`: `id`, `recibida`, `severidad`
    Leve 72 · Media 48 · Grave 24 h hábiles, `estado`, `abierta`, `plazo(zona:)`, `cuentaAtras(ahora:zona:)`),
    `fueraDePlazo(ahora:zona:)` (ENT-INC), `instante`, `textoFecha`, `siguienteID(en:hoy:)`, `operaciones(nueva:…)`.
    `CuentaAtras` (`minutosRestantes`, `fueraDePlazo`, `apurada` ≤ ¼ del plazo, `texto` «Quedan 23 h hábiles» / «Fuera de
    plazo hace 3 h hábiles», `textoPlazo`). `HorasHabiles.sumar` / `segundos`: **cuentan las horas de lunes a viernes,
    enteras** (una grave del viernes a las 10:00 vence el lunes a las 10:00); sin festivos; una fecha sin hora cuenta
    desde las 0:00.

## 9. Pantallas · Hoy, Decisiones y módulos de inicio (rol hoy-decisiones)

Ficheros: `Sources/TLSUI/Pantallas/Hoy{Pantalla,Datos,Almacen,Secciones}.swift`,
`Sources/TLSUI/Pantallas/Decisiones{Pantalla,Acciones,Tarjeta}.swift`, `Sources/TLSUI/Pantallas/Modulos/**`
(`ResumenDeArea`, `DisposicionInicio`, `AlmacenInicios`, `DatosModulos`, `VistasModulos`, `ModuloCaja`, `InicioModulos`) y
`Tests/TLSUITests/{Hoy,Decisiones,Modulos}/**`. Nada en TLSCore. Las firmas de los huecos (`HoyPantalla(sesion:)`,
`DecisionesPantalla(sesion:)`, `DecisionDetalle(id:sesion:)`, `ResumenDeArea(contexto:sesion:)`) no cambian;
`HoyPantalla.saludo(_:calendario:)`, `fechaLarga(_:)` y `diasLargos` siguen.

- **Datos de Hoy** — `DatosHoy.calcular(foto:conflictos:persona:estados:historial:pospuestas:reloj:)` (puro, `Sendable`,
  fuera del hilo principal): `panel` (`PanelMetricas`), `bandeja` (`BandejaDeDecisiones.consultar` con los conflictos de
  «Revisar» y la persona), `decisiones` (la bandeja sin lo pospuesto: **el número de la insignia**), `detalles`
  (`[id: DetalleDecision]`), `modulos` (`DatosModulos`), `hoy`, `hora`/`minutosAhora` (zona de `agenda.zona`), y
  `foco` (siempre uno: `panel.foco`), `pendientes`, `frase` (`panel.frase(decisiones: pendientes)`), `alertas`, `hayRojo`,
  `lineaMika` (`panel.lineaMika(hora: "8:45")`), `semana`, `cabe`, `textoDia` («2,5 h de 4», «Nada planificado»),
  `areasEnRojo`, `pospuestas` y `secciones(hayQueRevisar:)` → `[SeccionHoy]` (cabecera · foco · revisar si hay conflictos
  o repetidas · decisiones · **alertas solo si hay algo en rojo** · inicio · mika).
- **`AlmacenHoy.de(sesion)`** (`@Observable`, uno por empresa; lo comparten Hoy, Decisiones, `DecisionDetalle` y
  `ResumenDeArea`): `datos`, `estado` (`EstadoHoy`), `actualizar(forzar:)` (rehace con la foto de `AlmacenRelaciones`, los
  conflictos de la sesión y lo decidido; las llamadas van en fila y, al volver, los datos están al día; con la
  empresa cerrada no hace nada; mientras siga abierta vigila
  `sesion.revision`, `sesion.tarjetas` y `sesion.persona` y se rehace solo), y **pone la insignia magenta de Decisiones**
  en `sesion.barraLateral.datos[.decisiones]` (`insignia`, `palabraInsignia` «espera/esperan tu decisión»; sin nada, sin
  insignia). Lo que no va a la carpeta, en `hoy.json` del estado (Application Support), con aviso y «Deshacer»:
  `posponer(_ Tarjeta)` (al siguiente laborable), `descartar(_:)`, `apuntar(_:accion:)` (historial para CRITERIO),
  `posponer(decision:hasta:)`, `traer(_:)`. `EstadoHoy` (`tarjetas: [EstadoTarjeta]`, `historial: [DecisionTarjeta]`,
  `pospuestas: [id: AAAA-MM-DD]`, `podar(hoy:)`).
- **Decisiones** — `DetalleDecision.de(_:foto:hoy:tareas:resolver:)` (1-3-1: `quien`, `desde`, `evidencias`
  —enlaces de Problema, Pregunta, Datos que hay, Lo que propongo y Opciones, y el proyecto, la oportunidad y la empresa
  de la tarea; nunca lo privado—, `queCambia`, `siSePospone` —de la nota o del vencimiento y los 14 días de DIR-DEC14—,
  `motivoNoDecidir` —«Para aprobar» llega en F4—). `AccionesDecision` (puro, siempre como la persona):
  `planDecidir(_:decision:porque:opcion:foto:reloj:persona:)` → **una línea** en `Decisiones.md`
  (`RegistroDecisiones.anadir`, en `## <año>`, área en palabras y origen = enlace Markdown a la tarea, «Título (T-0001)»)
  **y** la tarea Hecha con «Decidido (opción N): …» en su Actividad, en un solo plan (deshacer deja los mismos bytes);
  `planResponder` (pregunta: «Respuesta: …» y Hecha; propuesta: comentario en Actividad, sigue abierta);
  `planDescartar` (Cancelada con el motivo). No van al registro ni responder ni descartar. `ErrorDecision`
  (`sinTarea`, `noSeDecideAqui`, `sinTexto`). `Decidir` (`@MainActor`): `decidir`, `responder`, `descartar` (por
  `sesion.escribirConDominio`, aviso «Decidido: «…». Queda en el registro de decisiones» y ⌘Z), `resolver` (conflictos:
  apartar el repetido, quedarse con la mía o la de fuera, iCloud; combinar o elegir versión → `.revisar`), `elegir`,
  `destino(_:)` (`.decision(de: ruta)` para tareas y borradores; `.decision("conflicto:<uuid>")`), `motivoSoloLectura`.
  `DecisionDetalle.buscar(_:en:)`. Vistas: `TarjetaDecisionVista`, `OpcionDecisionVista`, `EvidenciasDecision`.
  Teclas en el detalle: 1, 2, 3 (elegir, mientras no se escribe), ⌘↩ (Aprobar), «Aprobar con mis cambios», «Responder»,
  «Posponer» (mañana, el lunes, una semana) y «Descartar».
- **Módulos de inicio** — `InicioID` (`.hoy`, `.area(_)`; `clave`), `ModuloID` (29), `CatalogoModulos`
  (`definicion(_)` con título, área, descripción y tamaños —el primero, el de serie—; `disponibles(en:)`; `deSerie(_)`:
  Hoy = caja G, ritmo G, tu semana A, lo que cabe hoy M, cobros por confirmar P, oportunidades quietas P (M2-Hoy); cada
  área, lo de SISTEMAS §4.2), `DisposicionInicio` (puro: `visibles`, `ocultos` con tamaño y sitio, `maximo` = 8, `lleno`,
  `ocultar`, `mostrar`, `anadir`, `mover(_:_:)`, `mover(_:aLaPosicionDe:)`, `siguienteTamano`, `paraAnadir(_)`),
  `AlmacenInicios.de(sesion)` (`inicios.json` del estado; `disposicion(_)`, `cambiar(_:aviso:_:)` con «Deshacer»,
  `restaurar`, `editando`/`alternarEdicion`). `DatosModulos.calcular(foto:panel:pendientes:reloj:)`: `caja`
  (`DatosCaja`: `Tesoreria.serie` de los 5 periodos, saldo, meses de caja y estado de FIN-RUNWAY, fuente, motivo sin
  dato), `ritmo` (`RitmoArea` ×6), `semana`, `cabe` (`ElementoDia`: tareas planificadas, lo que vence hoy, reuniones,
  rutinas, citas inyectadas y cobros previstos; lo que tiene hora, primero), `cifras` (`CifraModulo`: cifra o
  `vacio` «Sin dato: …», línea, estado con palabra, enlace, fuente; un recuento real a cero se dice con palabras,
  «Ninguno»), `cuello`. Vistas: `InicioModulos(inicio:datos:sesion:titulo:hora:minutosAhora:)` (rejilla
  `MosaicoLayout`, «N de 8 módulos», «Añadir» → `GaleriaModulos`, «Editar inicio»: tiemblan —con «Reducir movimiento»,
  borde discontinuo—, arrastrar para ordenar o a «Ocultos del inicio», «−», ← →, tamaño; fuera de edición, el «…» y el clic
  derecho hacen lo mismo), `MarcoModulo`, `ModuloCifra`, `ModuloCaja` (Swift Charts; al pasar el puntero o con ← → el saldo
  de ese día, al arrastrar la diferencia del tramo; estimado en discontinua; un día sin dato corta la línea; «Ver como
  tabla»), `ModuloRitmo`, `ModuloSemana` («Libre» un día sin nada, nunca «0 h»), `ModuloCabe` (línea «Ahora»; vacío que
  dice que el Calendario del Mac llega en la versión 0.6), `ModuloCuello`. `RepartoFlex` (filas como `flex` de la maqueta).
- **Hoy** (vista): `CabeceraHoy`, `FocoHoy` (**el único** destacado violeta, `ContadorDestacados` = 1: chips de área,
  código, prioridad y tipo; qué pasa, recomendación, «Ver detalle» con por qué importa y qué pasa si no, «Posponer» con
  su consecuencia antes de confirmar, «Conectado con» con vista previa; el botón de la tarjeta: abrir la ficha, «Marcar
  hecha» por `TaskStore.cambiarEstado` y el dominio, ir a Control a fijar un umbral, al área, a Tareas; «Convertir en
  regla» desactivado hasta los asistentes), `PideTuDecision` (3 como mucho, insignia magenta con palabra, «Ver todas»),
  `AlertasHoy` (`accessibilityIdentifier` `hoy.alertas`), `LineaMika` («Hablar con Mika» desactivado: llega con los
  asistentes). «Seguir con la puesta en marcha» no sale hasta F3.

## 10. Pantallas · Tareas (rol tareas)

Ficheros: `Sources/TLSUI/Pantallas/TareasPantalla.swift`, `Sources/TLSUI/Pantallas/Tareas/**`, `Sources/TLSUI/Tareas/**`
y `Tests/TLSUITests/Tareas/**`; además, con la excepción de §3, una línea de `Navegacion/Destino.swift` y otra de
`Tests/TLSUITests/Integracion/RecorridoF1Tests.swift`. PLAN §4.2, §4.7 y §6.4 con Mosaico v2 (DISENO §3.4 «Tarea»).
Todo se escribe como la persona de la sesión, por `CommandBus`, con Deshacer; nada se aplica sin su clic; lo privado no
sale ni se toca.

- **Ruta:** `Destino.para(_:tipo:esCarpeta:)` lleva `tipo == .task` a `.tarea(ruta)` (y `sesion.destino(para:)`, ⌘K, las
  bases y Hoy con él). «Abrir como ficha» del tablero del proyecto sigue entrando en `.ficha`.
- **Pantalla Tareas** (`TareasPantalla(sesion:)`): cabecera azul noche (frase y cifras Para hoy · Vencidas · En revisión,
  «Nueva tarea» = `nav.hoja = .nuevaTarea`), «Revisar» (plegada en una línea), `BarraTareas` y `ListaTareas` o
  `TableroTareas`. Sin destacado violeta (como las bases).
  - `ModeloTareas(sesion:consulta:)` (`@Observable`, uno por pestaña): `cargar()` (foto de `AlmacenRelaciones`, filas fuera
    del hilo principal, una vez por generación), `filas`, `visibles`, `grupos()`, `columnas()`, `resumen`, `revision`,
    `contenedores`, `responsables`, `elegida`, `mover(_:a:)` y `moverAlLado(_:paso:)` (**solo** `estado` + entrada de
    Actividad), `aplicar(_ preparar:aviso:)` y `renumerarRepetidas()`.
  - `ConsultaTareas` (vista, `area`, `contenedor` = proyecto u oportunidad, `responsable` (`""` = sin responsable),
    `estado`, `fecha: FiltroFecha` Todas · Hoy (abierta y planificada hoy o antes, o vence hoy) · Semana (planificada o
    vence de lunes a domingo) · Vencidas (abierta con `vence` < hoy) · Sin programar (abierta sin `planificada`), `loMio`
    (`responsable` = la persona o su identificador), `busqueda` (todas las palabras, sin tildes, en número, título,
    proyecto, responsable y área), `verCanceladas`, `agrupar: AgrupacionTareas` Estado · Área · Proyecto u oportunidad ·
    Responsable · Sin agrupar). `pasa`, `filtrar` (lo urgente primero: vencidas, planificada, vence, número), `grupos`,
    `filtrando`, `quitarFiltros`. Recuerdo de `.tareas`: `filtros` `area`, `contenedor`, `responsable`, `estado`,
    `fecha`, `loMio`; `busqueda`; `extra` `tareas.vista`, `tareas.agrupar`, `tareas.canceladas`, `tareas.revisar`.
  - `FilaTarea` (la `Tarea` con `estado` reconocido —sin estado, Sin programar—, `estimacionH`, `contenedor` y su nombre,
    `esDeAsistente`, `vencida(hoy:)`, `paraHoy`, `enLaSemana`, `sinProgramar`, `esDe(persona)`). `LectorTareas.filas(foto:
    nombre:)` (sin lo privado; un proyecto u oportunidad privados no se nombran). `ColumnasTablero` (`estados(verCanceladas:)`
    Sin programar · Por hacer · En curso · En revisión · Bloqueada · Hecha (+ Cancelada), `vecina(de:paso:verCanceladas:)`,
    `columnas`, `vacio`). `ResumenTareas` (`paraHoy`, `vencidas`, `enRevision`, `abiertas`, `frase`).
  - `PlanesTarea.cambiarSoloEstado(_:a:store:autor:persona:)`: el plan del tablero (arrastrar, ⌘← ⌘→ con la tarjeta
    enfocada, «Mover a…» y las acciones de VoiceOver «Mover a …»): la línea `estado` y una entrada de Actividad
    («Estado: A → B.» con `tls:evento {"tipo":"estado","de","a","desde":"tablero"}`). Ni `cerrada` ni el sitio del fichero
    (criterio F2-2). Un asistente no puede cerrar.
- **Revisar** (`Pantallas/Tareas/RevisionTareas.swift`, `RevisarTareas.swift`): `RevisionTareas.de(foto)` → `legados`
  (`Tareas.md` no privados con los títulos de sus líneas), `adopcion` (identidades, relaciones —sin destinos privados—,
  ambiguas y ejemplos), `duplicados` (solo entre tareas no privadas; la más antigua se queda su número) y `correcciones`
  (tareas movidas en Finder). Planes: `planHeredados` (todos los `Tareas.md` en un plan, numeración seguida, una subida del
  contador, el fichero a `Archivo/`), `planAdoptar` (identidad + relaciones en un solo plan), `renumerar` (número nuevo y
  fichero renombrado con sus enlaces, `LinkRefactor`) y `planCorrecciones`. Vista: `RevisarTareas(sesion:)` (su propio
  modelo, abierta: para ponerla en «Revisar») y `RevisarTareas(modelo:)` (la de Tareas, plegada).
- **Ficha** (`TareaDetalle(ruta:sesion:)`): `CabeceraAzulNoche` (Tarea/Decisión/Pregunta · T-0042, título, de dónde
  cuelga, estado con menú, Número · Área · Responsable; «Abrir el proyecto/la oportunidad», «Ver en Decisiones» si es
  decisión o pregunta), el destacado violeta (`EstadoAsistenteTarea` si la lleva un asistente; si no, vencimiento y
  planificada) con «Empezar ahora» o «Marcar como hecha», «Descripción» (lo **único** editable del cuerpo: `BloqueSeccion`
  de fichas, `sustituirSeccion` con huella y «Cambió fuera»), el resto de secciones solo para leer, la Actividad y, a la
  derecha (o debajo por debajo de 900 pt), `PanelPropiedadesTarea`.
  - `ModeloTarea(ruta:sesion:)`: `ficha` (`FichaModelo`), `tarea`, `entradas`, `asistentes`, `alias`, `proyectos`,
    `cambiarEstado(_:nota:)` (con `cerrada` y Actividad, `TaskStore`), `empezarAhora()` (persona: En curso; asistente: Por
    hacer; y `planificada: hoy` si no tenía o era posterior, en la misma línea), `cambiar(_:a:aviso:)`, `planificar(_:)`
    (por `escribirConDominio`: ENT-04 corre al lunes y `avisoPlanificada` lo dice), `comentar(_:)` (las menciones a
    asistentes se guardan en el evento: `"menciones":"agente:comercial,…"`), `mover(a: MoverTarea.Destino)`.
  - `ActividadDeTarea.leer(_ texto:alias:)` → `[EntradaDeTarea]` de la más antigua a la más reciente: `clase` cambio ·
    comentario · asistente · sistema, `autor` («Comercial (asistente)», «La app», «Escrito en Obsidian»), `texto` (sin
    sintaxis de enlaces y con `@agente:x` como «@X (asistente)»), `resumen` (el evento en palabras: «Trabajo terminado ·
    Por hacer → En revisión», «Estado: A → B»…), `uso` («Uso: 0,04 USD»), `detalle` (para «Detalle técnico»: Ejecución,
    Aprobación, Función…), `menciones`, `pideAprobacion` (enlace a Decisiones), `sinEncabezado` (lo escrito debajo en
    Obsidian). `ActividadDeTarea.menciones(_:alias:)` y `legible(_:)`.
  - `EstadoAsistenteTarea.de(_:hoy:enMarcha:)`: sin empezar (Sin programar) · espera su día · en cola
    (`esListaParaAgente`) · trabajando (solo con `enMarcha`, lo dará F4) · espera tu respuesta (En revisión) · bloqueada ·
    terminado; `frase(asistente:hoy:)` y `palabra`.
  - `MoverTarea.preparar(_:a:foto:autor:)` → `RefactorPreview`: a `N · Área/Tareas/` (suelta: quita `proyecto`) o a la
    carpeta `Tareas/` de un proyecto (pone `proyecto`), con `area` de la carpeta nueva, todo en un plan con sus enlaces;
    nunca a lo privado. `MoverTarea.proyectos(_:grafo:)` (no privados ni cerrados).
- **⌘N** (`NuevaTareaHoja(contexto:sesion:)`): título y ⏎ crean; opcionales área (o el proyecto de la pantalla: ficha de
  proyecto o tarea de un proyecto, `proyectoDe(_:sesion:)`), quién la lleva (por defecto la persona) y día (ENT-04;
  con día nace Por hacer, sin él Sin programar). `NuevaTareaHoja.crear(titulo:area:proyecto:responsable:planificada:
  sesion:deshacer:) async throws -> VaultPath` (lo que hace ⏎) y al terminar entra en `.tarea(ruta)`.
- **Piezas** (TLSUI): `ResponsableTarea(identificador:tamano:)` (iniciales o «IA»), `VenceTarea` (icono y «Vencida» si
  venció), `MenuMoverA`, `MenuFiltro`, `CampoFechaTarea`, `EstadoTarea.tlsEstado`, `ResponsablesTarea.opciones` /
  `asistentes` (como `Responsables.opciones` pero sin lo privado).
- **Pruebas** (`Tests/TLSUITests/Tareas/`): `ConsultaTareasTests` (9), `CriteriosF2TareasTests` (8: F2-1, F2-2 al
  arrastrar y con ⌘→/⌘← y Deshacer, renumerar, privado, heredados, Adoptar, ficha) y `CapturasTareasTests` (con
  `TLS_CAPTURAS`: lista, tablero, «Lo mío» estrecha, Revisar abierta, ficha de asistente y de persona y la hoja ⌘N, en
  claro y oscuro; `build/capturas/f2-tareas/`).

## 11. Pantallas · Operación de Finanzas (con el Banco), Marca y Equipo (rol areas-b)

Ficheros: `Sources/TLSUI/Areas/Operacion/{Finanzas,Marca,Equipo}Operacion.swift` (los huecos, misma firma),
`Sources/TLSUI/Areas/Finanzas/**` (`BancoPantalla.swift` con su `init(cuenta:sesion:)`), `Sources/TLSUI/Areas/Marca/**`,
`Sources/TLSUI/Areas/Equipo/**` y `Tests/TLSUITests/Areas/{Finanzas,Marca,Equipo}/**`. No toca TLSCore ni el andamio.
Todo se escribe como la persona de la sesión (`sesion.autor`), con su aviso y Deshacer; nada se confirma, emite ni publica
sin un clic. Lo privado no entra (los lectores lo saltan con `layout.isPrivate`); sin dato, «Sin dato»; nunca 0.

- **Secciones** (pestañas en cápsula sin ⌃1–⌃9, recordadas en `nav.recuerdo(de: .area(a)).extra[clave]`):
  `SeccionFinanzas` (Caja · Cobros · Banco · Trimestre, clave `finanzas.seccion`), `SeccionMarca` (Calendario · Contenido ·
  Distribución · Conversaciones, `marca.seccion`), `SeccionEquipo` (Roles · Asistentes · Rutinas, `equipo.seccion`).
  `FinanzasOperacion.claveSeccion`, `MarcaOperacion.claveSeccion`, `EquipoOperacion.claveSeccion`.
- **Finanzas · lectura** — `LecturaFinanzas(foto:hoy:periodo:)` (pura, fuera del hilo principal, con el núcleo del rol de
  banco): `cuentas`, `saldo: SaldoCaja`, `runway`, `series: [RangoCaja: [PuntoCaja]]`, `cobrosPendientes`/`cobrosVencidos`,
  `totalVencido`, `sinConciliar`, `sinRevisar`, `propuestas`, `exactas`, `abiertos` (abiertos sin propuesta), `movimientos`,
  `avisos`, `hayEmitidas`, `hayDatosBanco`, `ultimoMovimiento`, `periodo`/`trimestre: ResumenTrimestre`/`paquete`,
  `heredados: PreparacionHeredada?` (`nil` sin ficheros en `Registros/importar/`), `metas` (ruta de `Metas.md`) y, por
  cuenta, `cuenta(carpeta:)`, `propuestas(de:)`, `abiertos(de:)`, `movimientos(de:)`. Textos: `TextoFinanzas` (`euros` de
  céntimos con «−», `eurosConSigno`, `meses`, `porcentaje`, `fuente(SaldoCuenta)`, `dias`), `VariacionCajaFinanzas`
  (`texto` «−763,70 € · −3,9 %», `frase(rango)`), `TramoCajaFinanzas.de(serie)` (tramos de la gráfica: se corta donde no
  hay saldo; discontinuo lo estimado), `PastillaEstimadoFinanzas`, `SelectorPeriodoCajaFinanzas`.
- **Finanzas · modelo** — `ModeloFinanzas(sesion:cuenta:)` (`@Observable`; uno por pantalla): `cargar(forzar:)`,
  `elegirPeriodo(_:)`, `rango`, importar = `previsualizar(url:)`/`previsualizar(datos:nombre:)` (sin cuenta fija elige la
  que ya tiene más movimientos de ese fichero) → `vista: VistaPreviaExtracto` (`resumen` «31 movimientos · 2 nuevos · 29 ya
  importados»), `elegirCuenta(_:)`, `leerAdivinando()`, `cancelarImportacion()`, `importar(deshacer:)` (con 0 nuevos no
  escribe); `confirmar(_:deshacer:)`, `confirmarLasExactas(deshacer:)`, `ignorar(_:motivo:deshacer:)`,
  `prepararPaquete(deshacer:)` (no pisa ni envía), `cargarHeredados(deshacer:)`, `anadirRunwayAMetas(deshacer:)`;
  `hecho`, `error`, `errorImportacion`, `trabajando`, `motivoSoloLectura`, `cuentaFija`. Escritura: importar, confirmar y
  heredados por `sesion.escribirConDominio(plan:)` (heredados con `motor.setModoImportacion(true)`: no disparan reglas);
  ignorar, paquete y `Metas.md` por `sesion.escribir`.
- **Finanzas · vistas** — `CajaFinanzas` (cifra de hoy, variación del periodo, gráfica de Swift Charts con área, línea
  discontinua en lo estimado, hueco sin dato, puntero, ← → Inicio Fin Esc y acción ajustable de VoiceOver, «Ver como
  tabla»; «Meses de caja» con la meta y la alerta de FIN-RUNWAY —oculto si la meta aún no se decidió, con «Fijar la
  meta»—; sin FIN-RUNWAY en `Metas.md`, «Medirlo en Control» añade su fila **sin meta** con «Propuesta: meta 3 meses,
  alerta 1 mes» en «Por qué»; cuentas con su fuente; sin datos del banco, «Sin datos del banco: importa un extracto»),
  `CobrosFinanzas`, `BancoContenido` (soltar o elegir el CSV, vista previa con lo nuevo primero, propuestas con su motivo y
  «Confirmar»/«Confirmar las exactas», «Ignorar…» con motivo, heredados con «Cargar en preparación»), `TrimestreFinanzas`
  (‹ T3 2026 ›, plazo, 303/115/111/130 estimados con lo que falta, libros, «Preparar paquete para la gestoría»),
  `BancoPantalla` (cabecera azul noche con saldo, sin conciliar y último movimiento de la cuenta o de todas).
  `AvisosFinanzas(modelo:)`. El número de meses de caja de Finanzas › Caja es el de `FilaControl` (el mismo que el
  destacado del andamio); la salida media de `Tesoreria` solo se dice si no hay número clave.
- **Marca** — `LecturaMarca(foto:hoy:)`: `piezas: [PiezaMarca]` (`tipo`, `estado: EstadoPieza?`, `pilar`, `canales`,
  `publicar`, `publicado`, `evidencia`, `alcance`, `impresiones`, `interacciones`; `dia`, `movible`), `conversaciones:
  [ConversacionMarca]` (`quien`, `canal`, `fecha`, `estado: EstadoConversacion`, `pieza` resuelta, `piezaTitulo`,
  `loQueDijo`), `publicadas`, `piezas(en:)`, `calendario(anio:mes:)`, `sinFecha`, `conversaciones(de:)`, `canales:
  [CanalMarca]` (publicadas, alcance e interacciones = suma de las que lo dicen o `nil`, conversaciones y cualificadas);
  `nombreCanal`, `nombreTipo`, `cifra`. `ModeloMarca(sesion:)`: `mover(_:a:deshacer:)` (solo `estado`; a Publicado, también
  `publicado: <hoy>` si no lo tenía), `cambiarDia(_:a:deshacer:)` (`publicar`, o quitarlo; lo publicado no se mueve),
  `proponerAVentas(_:deshacer:)` (una tarea en `2 · Ventas/Tareas/` con `conversacion:` y la conversación en «Propuesta a
  Ventas», un solo plan). Escribe por `escribirConDominio`. Vistas: `CalendarioMarca` (mes L–D, arrastrar a otro día o a
  «Sin fecha»; menú y acciones de VoiceOver «Un día después/antes», «A la semana siguiente», «Quitar la fecha»),
  `TableroMarca` (Idea → Publicado y Descartadas plegadas; arrastrar o «Mover a…»), `DistribucionMarca` (MAR-PUB, MAR-QCONV,
  una tarjeta por canal y la tabla de lo publicado), `ConversacionesMarca`. «Generar borrador de pieza», desactivado con
  «Llega con los asistentes».
- **Equipo** — `LecturaEquipo(foto:hoy:)`: `roles: [RolEquipo]` (persona o asistente por `clase`, `areas`, `ocupante`,
  `mision`, `numeros`; primero las personas), `asistentes` (de `.tls/config.yaml › agentes`: solo `activo` y
  `presupuesto_mes_usd`), `hayBitacora`, `bitacora` (12 últimas líneas de `6 · Equipo/Bitácora/`), `usoMesUSD` (`nil` sin
  bitácora), `topeMesUSD`, `textoUso` («35 % de tu tope», «Sin tope», «Sin dato»), `semanas` (6 lunes, el último el de hoy),
  `rutinas: [FilaRutina]` y `rutinasCaidas` (EQU-RUT: dos semanas acabadas seguidas sin hacerse). Rutinas = fichas
  `routine` y registros `routine_log` (por su `rutina`, por la carpeta `Rutinas/<rutina>/` o, sin ficha, por su carpeta:
  `dia` → «Rutina diaria», `semana` → «Rutina semanal»…). Celda (`CeldaRutina`, `ResultadoRutina`): ✓ hecha · ✕ no se hizo ·
  – no tocaba (antes de existir) o pendiente (semana en curso); diarias, «n de m días» laborables. `ModeloEquipo` solo lee.
  Vistas: `RolesEquipo` (EQU-ROLES arriba), `AsistentesEquipo` (vacío explicado mientras no haya asistentes en la
  configuración ni bitácora; los roles de asistente escritos, debajo), `RutinasEquipo` (rejilla). «Revisar asistentes»
  lleva a la sección.
- **Pruebas** — `Tests/TLSUITests/Areas/Finanzas/` (`FinanzasOperacionTests`: Ribera a 19/10, F2-4 importar dos veces da
  «0 nuevos», ningún cobro sin clic y con él Ganada y un proyecto, «Confirmar las exactas», ignorar, F2-7 los 71
  heredados sin ninguna fila confirmada, FIN-RUNWAY en Control, solo lectura, privado y «Sin dato»; `ApoyoAreasB`;
  `CapturasAreasBTests` con `TLS_CAPTURAS`), `Areas/Marca/MarcaOperacionTests` y `Areas/Equipo/EquipoOperacionTests`.
  Capturas en claro y oscuro: `build/capturas/f2-areas-b/`.

## 12. Integración de F2 (rol integración)

Lo que une las piezas de los demás roles. Todo con pruebas en `Tests/TLSUITests/Integracion/CriteriosF2Tests.swift` (los 8
criterios de PLAN §9 F2, uno por prueba, «una semana en la copia» y R1) y `Tests/TLSCoreTests/Metricas/UnaSolaCajaTests.swift`.

- **Reglas conectadas al escritor.** Con escritor, **toda** escritura de la persona por `sesion.escribir(_:)` y
  `sesion.escribir(plan:)` pasa por el motor de la empresa: `MotorDeDominio.escribirYAtender(_ plan)` /
  `escribirYAtender(_ comando, autor:)` (TLSCore, nuevo) escribe por el mismo `CommandBus`, deduce los eventos
  (`EventDeriver`), los guarda en la bandeja de salida y deja que las reglas los atiendan como `Autor.sistema`, con su
  idempotencia. **Sin** volver a mirar las invariantes (el editor no puede esperar a leer la carpeta entera; las
  pantallas que cambian estados usan `escribirConDominio`, que sí las mira). Sin escritor, como antes. Un plan que no es
  de una persona (`Autor.sistema`/agente) no pasa por aquí. `MotorDeDominio.registrar` ya no lee la carpeta entera: solo
  su estructura (`VaultLayout.load`).
- **Al abrir la empresa** (`ContenidoEmpresa`, `.task(id: sesion.puedeEscribir)`): se crea el motor (que termina lo
  pendiente, `procesarPendientes()`) y `AlmacenHoy.de(sesion).actualizar()` pone la insignia de Decisiones aunque la
  ventana se restaure en otra pantalla.
- **Deshacer la cadena.** `despuesDeEscribir`/`registrarDeshacer(_:…, cadena:)` reciben los planes que escribieron las
  reglas (`VaultSession.planesDeReglas(ResultadoDominio)`). ⌘Z y el «Deshacer» del aviso llaman a
  `sesion.deshacer(plan:cadena:)`: deshace de uno en uno, del más reciente al plan de la persona, solo si cada uno es el
  último que se puede deshacer (si no, «Antes hay que deshacer «…»» o «Deshice una parte…»); lo creado va a `Archivo/`.
  Aviso: «Deshecho, también lo que hicieron las reglas». Después, `DominioEmpresa.olvidar(_:de:)` →
  `EstadoDominio.olvidar(planes:)` (nuevo): los eventos de esos planes pasan a `EstadoEvento.deshecho` (nuevo) y lo que
  las reglas apuntaron por ellos deja de contar (las claves viejas se guardan con `#deshecho:<id>`; no se borra nada),
  así que **si la persona lo repite, las reglas vuelven a actuar** (confirmar, deshacer y confirmar otra vez: Ganada y 1
  proyecto). También `MotorDeDominio.olvidar(planes:)`.
- **VEN-07, una sola regla.** `LecturaDominio.recibosConfirmados(de:)` y `tieneCobroConfirmado(_:)` (nuevos): cuenta el
  cobro confirmado por una persona en `pagos.csv` **o** su recibo (`tls_type: receipt` con `confirmado_por` que no es
  un asistente, el «Confirmar el cobro» de la factura en F1). Lo usan VEN-07 (`Invariantes`), el aviso de ENT-01 y la
  regla `oportunidad.ganada → su proyecto`. `GrafoRelaciones.cobroConfirmado` (F1) deja de aceptar una factura que solo
  dice «Cobrada»: ahora es la misma regla.
- **Una sola caja.** `Tesoreria.runway` adopta «mes cubierto entero» y redondea la salida media al céntimo: con Ribera
  a 5/10, 19/10 y 2/11 da lo mismo que `KPIEvaluador` (caja, meses de caja, salida media, FIN-AR y FIN-UNREC).
- **ENT-INC en el núcleo.** `FotoMetricas.incidencias` (los `Incidencias.md` junto a cada proyecto de entrega, sin lo
  privado ni lo archivado) y `KPIEvaluador` «ENT-INC» con la cuenta atrás de `RegistroIncidencias` (ahora = el día de la
  carpeta a la hora del reloj). Control y Hoy ya no dicen «Sin dato» si hay registros.
- **Revisar.** `RevisarPantalla` pinta también las tarjetas de las tareas (`RevisarTareas(modelo:abierta:)`, init nuevo;
  heredados, Adoptar, números repetidos, tareas movidas). «Nada que revisar» solo si tampoco hay de esas.
- **Galería con PDF (R1).** `VistaGaleriaBase.tarjeta` pinta `MiniaturaDeRuta` de la primera página (48×60 pt en M y L,
  36×44 en S). La base **Gastos** ofrece ya la vista Galería (`CatalogoBases`: `[.tabla, .lista, .calendario, .galeria]`):
  es la que trae el PDF de cada fila (`documento` de `recibidas.csv`).
- **Tareas desde el tablero del proyecto (F1).** ↩, doble clic, «Abrir la tarea» y «Abrir en pestaña nueva» van a
  `.tarea(ruta)`; «Abrir como ficha» sigue en `.ficha`.
- **La ficha de una decisión o pregunta** (`TareaDetalle`): el destacado ofrece «Decidir en Decisiones» (queda su línea
  en el registro) en vez de «Marcar como hecha».
- **Lo privado en el núcleo de tareas.** `LegacyTasksMigrator.encontrar()` y `TaskStore.duplicados()` ya no incluyen lo
  privado.
- **`AlmacenRelaciones.actualizar()`** (F1): la carga se quita sola de `carga` al terminar y, sin foto (empresa cerrada),
  no se insiste: ya no puede dar vueltas en el hilo principal.
- **Plantilla `1 · Dirección/Metas.md`** (y su copia en `docs/propuesta/plantillas`): VEN-WON «Ventas cobradas del mes»,
  FIN-AR «Cobros vencidos», EQU-HEALTH «Asistentes sanos», EQU-COST «Coste de los asistentes del mes» (el sentido de
  `kpi.json`) y la fila **FIN-RUNWAY** «Meses de caja» con «Propuesta: meta 3 meses, alerta 1 mes».
- **`ProcessRunner` (TLSAgents):** el tope de tiempo, el SIGKILL y la lectura de stdin/stderr van en colas serie propias
  (no en las globales): bajo mucha carga (todo el paquete de pruebas a la vez) el tope ya no se retrasa.
- **Capturas:** `make capturas` pinta F1 y F2 (`CapturasF2Tests`, 22 pantallas en claro y oscuro) e índice conjunto;
  `CapturasF1Tests.lista` y `escribirIndice(_:titulo:)`.
- **Versión 0.3.0** (`Config/Base.xcconfig`). Guía manual: `docs/pruebas/F2.md`.

## 13. Revisión final de F2 (corrector final)

Aplica los hallazgos de las dos revisiones (cálculos y datos; diseño y accesibilidad). Las pruebas de la revisión de
cálculos (`Tests/TLSCoreTests/RevisionF2CalculosTests.swift`, `Tests/TLSUITests/RevisionF2DatosTests.swift`) ya no
llevan `withKnownIssue`: quedan como regresión. Las de diseño, en `Tests/TLSUITests/RevisionFinalF2Tests.swift`.

**Escritura (TLSCore, amplía F1):**
- `WriteOp.insertCSVRows(VaultPath, rows: [[String: String]], key: String)` (nuevo caso) y
  `CSVDocument.insertNew(_:key:)`: añade filas al final en el separador y el orden de columnas del fichero, leyéndolo una
  sola vez, y **nunca pisa ni repite**: si la clave de alguna ya está (o se repite entre ellas) lanza
  `WriteError.filaYaExiste(String)` (nuevo) y el plan entero no se escribe. Lo usan `CSVEscritura.filasNuevas`
  (importar un extracto, las filas `PAG-…` de `pagos.csv` al conciliar y los heredados). `Reglas.comprobar` e
  `Invariantes` la tratan como `upsertCSVRow` (una regla no escribe cobros; un cobro de una persona en el mismo plan
  cuenta para VEN-07).
- `MotorDeDominio.escribirYAtender` mira ahora dos invariantes sin leer la carpeta entera:
  `Invariantes.fechasLaborables(_:layout:texto:)` (ENT-04 solo con las fichas del plan: `mergeFrontmatter` y `create`; el
  guardado del editor no se toca) y, si `Invariantes.pasaAGanada(_:)`, VEN-07 con la carpeta entera
  (`DominioError.bloqueado`). `ResultadoDominio.invariantes` trae el aviso de ENT-04; `sesion.escribir` lo enseña («… pasa
  al lunes 26 oct») y un bloqueo de VEN-07 sale en ámbar.

**Datos y números:**
- VEN-07 por las bases: `ReglaGanada.calcular(…, recibos:, …)` ya no acepta una factura que solo dice «Cobrada»; cuenta la
  fila confirmada de `pagos.csv` o el recibo confirmado por una persona (como `LecturaDominio.tieneCobroConfirmado`). La
  columna Estado de Facturas no se edita en la base ni en su tablero («La emisión y el cobro se confirman con su acción»).
- `ModeloFinanzas`: las escrituras van en cola (`enCola`), `trabajando` se enciende con el clic. Dos «Confirmar» seguidos
  dan `PAG-…-001` y `PAG-…-002`; un doble clic en «Importar» escribe una sola vez.
- ENT-ONTIME: `FotoMetricas.TareaMedida.cerradaEn` = `cerrada` o, si falta (el tablero cambia solo `estado`, criterio
  F2-2), el día de la última entrada de Actividad que la pasó a ese estado.
- ENT-INC determinista: `FotoMetricas(snapshot:hoy:ahora:)` y `FotoMetricas.ahora` (`PanelMetricas.calcular` pasa
  `reloj.ahora`).
- VEN-WON («Ventas cobradas del mes»): cuenta el día del cobro confirmado (`FotoMetricas.Oportunidad.cobrada`: fila
  `confirmado` de `pagos.csv` por su factura o su proyecto, o el recibo de su factura), como dice «Cómo se mide» de
  Metas («Σ valor de oportunidades ganadas (cobro confirmado) en el mes»). Con VEN-07 es el mismo día que `cerrada`;
  sin cobro encontrado, vale `cerrada`. **En Ribera cambia lo que se ve:** las seis Ganadas se cobraron de mayo a
  septiembre (su `cerrada` es el día de la conversión), así que VEN-WON de octubre es 0 € (antes 660 €), el foco dice
  «6.000 € de ventas cobradas al mes: vas al 0 % de lo previsto» y el ritmo de la empresa baja de 84 a 67.
- `Tesoreria.linea`: un saldo inicial con fecha posterior a hoy es desconocido (como `KPIEvaluador`).

**Diseño y claridad (TLSUI salvo lo dicho):**
- P1 · caja sin extracto: `PuntoCaja.conMovimientos` y `PuntoCaja.hayMovimientos(_:desde:hasta:)` (TLSCore);
  `VariacionCajaFinanzas.sinMovimientos`; `ModuloCaja.variacion(_:)`. Sin movimientos del banco en el tramo: «Sin dato:
  falta el extracto de este periodo», nunca «0,00 €» ni «no cambia»; la pastilla «Estimado» no acompaña a «Sin dato».
- «Rojo» es una cosa: `PanelMetricas.enAlerta(_:)` y `enAlerta(codigo:)`; `ritmoAreas` va «En alerta» solo si el área
  tiene algo en Alertas (si no, «Atención»; el cuello sigue con el ritmo tal cual); `NumerosDelNucleo.ritmo` igual por
  número; los objetivos (`OperacionComun.ritmo`) nunca van en rojo; el foco de Hoy (`FocoHoy(…, enAlerta:)`) dice «En
  alerta» o «Atención» y ya no lleva el chip de tipo. Título del foco: «… vas al 53 % de lo previsto».
- `Umbral.textoVisible` (TLSCore): meta y alerta con el formato de la app («6.000 €», «3 meses»); `ValorKPI.textoMeta`,
  `textoAlerta`, el texto de las alertas, la frase del ritmo y `FilaControl.textoMeta/textoAlerta` lo usan. Para editar,
  la celda tal cual.
- Resumen de Entrega: el módulo de incidencias es ENT-INC (con «N abiertas»), como Operación.
- Cabecera de área sin `estado:` en `Área.md`: no se pinta «Sin estado». Barra lateral: «N para hoy» bajo Tareas (lo que
  cuenta la cabecera de Tareas) y «N quietas» en ámbar bajo Ventas (abiertas sin contacto desde hace 7 días o más).
- Decisiones: el grupo de tus fichas `tipo: decision` se llama «Por decidir» (antes «Propuestas de mejora»); el dato de la
  cabecera también.
- Control: debajo de cada número, la frase llana del catálogo (`FilaControl.enPalabras`); la fórmula de «Cómo se mide», en
  un «Cómo se calcula» plegado (`ComoSeCalcula`). La cabecera ya no habla de «celdas de Metas.md».
- Marca: las piezas del calendario y las tarjetas del tablero reciben el foco con su anillo (Tab), ↩ las abre y ⌘← ⌘→
  las mueven (al día o a la columna de al lado); las piezas del calendario miden 28 pt (`TecladoPieza`).
- Menores: «Oportunidades sin valor, estado, servicio o responsable»; el veredicto del cuello sin «regla dura» y con el
  mismo número de reglas que Alertas; iconos propios por columna en Tareas (`simboloColumna`); «Ninguna» en vez de 0 en la
  cabecera de Tareas; la pista de VoiceOver sin «Doble toque»; los botones de contorno desactivados con el texto al 100 %
  (contraste); «Sin dato» en vez de un 0 en «Qué pasa» del foco sin dato; textos sin «En CSV» ni «versión 0.6».
- Palabras llanas (P3): una tarea sin proyecto dice «Sin proyecto» (antes «Suelta»; el grupo de la lista, «Sin
  proyecto»); la tarjeta de Revisar que añade tipo, identificador y relaciones se llama «Completar las fichas de la
  carpeta» con el botón «Completar» (antes «Adoptar la carpeta»; el código sigue siendo `Adopter`/`planAdoptar`); en
  pantalla, «la nota Metas de Dirección» en vez de «Metas.md», y el aviso «Meses de caja añadidos a Metas» en vez de
  «FIN-RUNWAY añadido a Metas.md».

**Comprobado (23/10, 15:20):** `swift test` y `make test`: 881 pruebas en 147 suites, sin `withKnownIssue` de F2 ni
avisos; `make capturas`: 70 capturas; `make dmg`: `dist/The-Last-System-0.3.0.dmg` (build 4), SHA-256
`e277a5698f07825f0092cdd9feaf617c52b8c95267019cdf16fefbbfeabaebae`, firma de equipo también dentro del disco. Falta
mirarlo con la app abierta: arrastre real, foco y orden del tabulador, VoiceOver, ⌘N del menú frente al de una base y
las teclas 1-2-3 en una decisión.

## Cambios pedidos

**Estado tras la revisión final (23/10).** Atendido (§13): `WriteOp.insertCSVRows` (una sola lectura del CSV, nunca
pisa: era «`upsertCSVRows`»); ENT-04 y VEN-07 en `escribirYAtender`. **Sigue pendiente**, con su motivo:
- **El ejemplo de Ribera** (no es de este rol: cambia lo que ven las pruebas): poner `estado:` en cada `Área.md` como en
  la maqueta (Dirección, Ventas, Entrega y Finanzas activas; Marca preparada; Equipo en reposo); quitar del ejemplo las
  palabras del glosario («agentes», «runway»: `1 · Dirección/Metas.md`, `6 · Equipo/Área.md`, `Empresa.md`, los roles y
  `6 · Equipo/Tareas/t-0002…`) y ampliar el lint del glosario a los `.md` del ejemplo; y las fechas de la conversión
  (`creada`, `aceptada` y `cerrada` = 19/10 en las oportunidades), que también sesgan VEN-CONV.
- **Decisión de Manu:** VEN-WON por el día del cobro confirmado (hecho en §13, se revierte en una línea de
  `KPIEvaluador`) y FIN-RUNWAY con «salida fija» (Metas y Programa) o con todas las salidas, como ahora (7,9 meses; sin la
  «Retirada del titular», 8,5).
- El guardado del editor (`saveText`) puede escribir `estado: Ganada` sin pasar por VEN-07 y no corrige ENT-04: no se
  reescribe lo que teclea la persona; haría falta avisar en el editor.
- Observaciones de la revisión de cálculos, de gravedad baja y sin prueba: `KPIEvaluador`, el trimestre y el conciliador
  cuentan las filas heredadas `estado_revision: pendiente` que `Tesoreria` deja fuera (tras «Cargar heredados» las dos
  cajas pueden diferir hasta revisarlas); los chequeos y la bandeja no filtran fichas con `creada` posterior a hoy (solo
  se nota al mover el día del ejemplo); la bandeja compara el responsable por nombre exacto y «Lo mío» de Tareas también
  por su identificador; la conversión del tablero CRM no aplica «Ver solo lo de este rol»; un recibo hecho con la
  plantilla cuenta para VEN-07 aunque no lleve importe.
- Crear `pagos.csv` o `movimientos.csv` cuando aún no existen sigue con `.create` (que añade « (2)» en vez de fallar);
  solo pasa la primera vez y con dos ventanas a la vez.
- Diseño (P3) no atendidos: columnas del tablero de Tareas fuera de la vista sin aviso; miniatura del PDF más grande en
  la Galería; vista del cliente (fecha sin formato en lo que escribe el cliente, colores de la incidencia, «Programada»
  con el check de «Hecha»); títulos de módulo a dos líneas y «Pide tu decisión» en tres columnas en ventana estrecha;
  «Tu semana» con la marca «hoy». Son de presentación y no cambian ningún dato; piden mirarlo con la app abierta.

**Estado tras la integración (23/10).** Atendido (ver §12): Galería con miniatura (y Galería en Gastos); insignia al
abrir; motor por sesión con `procesarPendientes()` al abrir; reglas tras cada plan de la persona; Deshacer de la cadena
(areas-b) con «olvidar» para poder repetir; VEN-07 igual en el dominio y en F1 (incluye el recibo); una sola caja
(`Tesoreria` con «mes cubierto entero» y redondeo); ENT-INC en `KPIEvaluador`; `RevisarTareas` en «Revisar»; plantilla de
Metas alineada con `kpi.json` y con FIN-RUNWAY; tablero del proyecto → `.tarea`; lo privado fuera de
`LegacyTasksMigrator`/`duplicados`; `AlmacenRelaciones.actualizar()` sin vueltas. **Sigue pendiente** (con su motivo):
- `WriteOp.upsertCSVRows` y añadir columnas a un CSV (banco): no hacen falta para Ribera ni para los criterios; el banco
  ya usa `anadirLinea` desde 51 filas. Para F3 (importar la carpeta real).
- Un recibo de F1 («Confirmar el cobro» en la factura) no da aún `cobro.confirmado`: VEN-07 ya lo acepta y, al pasar la
  oportunidad a Ganada a mano, la regla abre su proyecto; que lo haga solo pide que la regla de VEN-07 sepa leer un
  recibo (no solo una fila de `pagos.csv`) y cambia pruebas de F1. Para F3.
- ENT-ARR48 (horas del cobro a la primera sesión agendada) sigue «Sin dato»; el Viaje de la ficha de proyecto de F1 sigue
  leyendo `## Viaje` de `Proyecto.md` y no `Portal.md` (areas-a); «Preparar propuesta» en Ventas; festivos en las horas
  hábiles (F5, Calendario); el plan de 4 semanas como proyecto interno (dominio); propuestas de regla en modo
  `asistido` (F4: `WriteOp` aún no es `Codable`); `sesion.hayQueRevisar` no cuenta las tarjetas de las tareas (Hoy
  enseñaría «Revisar» por ellas: hace falta calcularlas fuera del hilo principal).
- `Chequeo` y `TarjetaBuilder` siguen calculando DIR-03, ENT-01 y DIR-DEC14 desde las fichas (misma regla que
  `Invariantes`; las pruebas fijan el resultado) y no leen `Invariantes.atenciones()` ni la bandeja.
- `TaskStore.cambiarEstado(soloEstado:)` con entrada de Actividad (para que el tablero del proyecto de F1 la apunte) y
  los campos `estimacion_h`, `dedicadas_h`, `bloqueada_por`, `capacidad` en `Tarea`.
- «Ver solo lo de este rol» aún no filtra las pantallas de Operación de Finanzas, Marca y Equipo.


- **andamio → bases/integración (R1, Galería):** la miniatura de la primera página del PDF en la vista Galería. En
  `Sources/TLSUI/Bases/VistaListaBase.swift`, `VistaGaleriaBase.tarjeta`, cambiar `if f.documento?.ext.lowercased() ==
  "pdf"` por `if let doc = f.documento, doc.ext.lowercased() == "pdf"` y el hueco `Image(systemName: "doc.richtext")…`
  (líneas 133–139, «Hueco de la miniatura… (llega en F2)») por
  `MiniaturaDeRuta(ruta: doc, sesion: modelo.sesion, lado: 120).frame(width: 36, height: 44).background(RoundedRectangle(cornerRadius: 6).fill(TLSPaleta.bandeja.color)).clipShape(RoundedRectangle(cornerRadius: 6))`
  (más grande en `tamanoGaleria` M y L si se quiere). Ya filtra lo privado, no descarga de iCloud y usa la caché de la
  empresa. Ningún rol de pantallas tiene `Bases/`: lo hace la integración de F2.
- **andamio → cimientos (hecho, 23/10):** una línea en `State/VaultSession+Lectura.swift` (`nombre(de:)` lleva `.tarea`,
  `.decision` y `.banco` a `nombreF2(de:)`, en `Navegacion/RutasF2.swift`), porque el `switch` es exhaustivo.
  `Pantallas/AreaPantalla.swift` se retira (lo sustituye `Areas/AreaScaffold.swift`; `AreaScaffold.estado(_:)` hace lo
  que hacía `AreaPantalla.estado`), y `Pantallas/PantallasSencillas.swift` se queda solo con Asistentes.
- **andamio → núcleo (hecho, 23/10):** `Tests/TLSCoreTests/TiposDeFichaTests.swift` esperaba `schemaVersion == 2`; ahora
  `>= 2` (la versión 3 es la de los PDF y la comprueba `TextoPDFTests`).
- **andamio → dominio/números:** «Activar» escribe `activada: AAAA-MM-DD` en `Área.md` (para avisar si se activa otra
  área antes de 30 días). No está en la plantilla «Cabecera de área» (SISTEMAS §2.3); si el dominio prefiere otro sitio
  (p. ej. una línea en `Decisiones.md`), que lo diga y el andamio lo lee de allí.
- **andamio → números:** `NumerosDelNucleo` (TLSUI) traduce `ValorKPI` al andamio: `EstadoRitmo` adelantado/en ritmo →
  «En ritmo», atención → «Atención», en riesgo/crítico → «En alerta». Si el número trae ritmo propio para el área
  (`RitmoArea`), se puede usar en la cabecera en lugar del «más atrasado» de las filas.
- **banco → pantallas (areas-b, `BancoPantalla` y Finanzas › Caja/Trimestre):** importar = `ImportadorExtracto.vistaPrevia`
  (enseñar `resumen`, tres filas y, si `guardaFormato`, el formato adivinado) y, con el OK, `vista.plan(autor:)`.
  Confirmar = `Conciliador.confirmar`/`confirmarLasExactas` con la persona de la sesión y su `plan` **por
  `MotorDeDominio.ejecutar(plan)`** (así sale `cobro.confirmado` y VEN-07 deja Ganada y un proyecto); si se escribe con el
  `CommandBus`, después `motor.registrar(…)` como pide el dominio. `LegacyMovementsImporter`: escribir su plan con
  `motor.setModoImportacion(true)`. Gráfica: `Tesoreria.serie(rango)`, línea discontinua en los puntos `estimado` y
  hueco donde `saldo == nil`; «Sin datos del banco: importa un extracto» = `runway.motivo`.
- **banco → números:** `KPIEvaluador` calcula la caja por su cuenta (en `Double`). Da lo mismo que `Tesoreria` con Ribera
  (26.664,65 €, 7,9 meses, FIN-AR 0, FIN-UNREC 1); si se quiere una sola fuente, `Tesoreria` da `saldo`, `runway`,
  `totalVencido` y `sinConciliar` en céntimos exactos.
- **banco → dominio:** `EventoFinanzas.clave` es la misma que `EventoDominio.clave`, así que entregar los dos no repite
  nada. Ojo: si se vuelve a importar un extracto cuyo original ya estaba guardado (mismos bytes), no aparece fichero nuevo
  en `Extractos/` y el `EventDeriver` no da `extracto.importado`; `VistaPreviaExtracto.evento` sí lo da.
- **banco → escritura (sin dueño en F2; para la integración):** `guardarFila` relee y reescribe el CSV entero en cada
  fila: 600 filas nuevas en un plan tardaban 22 s. El banco usa una sola `anadirLinea` a partir de 51 filas nuevas
  (0,8 s). Lo limpio sería una operación `WriteOp.upsertCSVRows` (varias filas, un solo análisis del fichero).
- **banco → escritura:** `CSVDocument` no sabe añadir columnas. `emitidas.csv` (cabecera de `Esquema.md`) no tiene base,
  IVA ni retención: el 303 de las emitidas sale de su ficha de factura y, en las cargadas de ficheros heredados, queda
  «Sin dato» (`PreparacionHeredada.columnasQueNoCaben` lo dice). Si se decide ampliar el esquema, hace falta añadir
  columnas al final sin tocar las filas.
- **banco → diccionario (SISTEMAS §1.5):** clave nueva opcional en `.tls/config.yaml`: `fiscal: {forma: autonomo|sociedad}`
  (si no está, se deduce de la letra del NIF de `facturacion`). Decide si aplica el 130.
- **números → banco (una sola caja):** `KPIEvaluador` calcula FIN-CASH, FIN-RUNWAY, FIN-AR y FIN-UNREC por su cuenta (en
  `Double`) con las mismas reglas que `Tesoreria` (caja `nil` si falta una cuenta; traspasos declarados o casados en 3
  días; 3 meses completos). Con Ribera a 19/10 coinciden. **Una diferencia:** para la salida media, `KPIEvaluador` solo
  cuenta los meses que los movimientos cubren **enteros** (hasta el último movimiento); `Tesoreria` cuenta cualquier mes
  pasado desde el primer dato. Ribera a 2/11 (el extracto acaba el 17/10): `KPIEvaluador` 7,9 meses (julio–septiembre);
  `Tesoreria` 11,0 (agosto–octubre, con medio octubre: 2.413,97 € al mes en vez de 3.393,52). Propongo que `Tesoreria`
  adopte «mes cubierto entero» (un extracto atrasado no debe inflar los meses de caja). En la integración, decidir si
  `KPIEvaluador` delega en `Tesoreria` (céntimos exactos) o se queda así; los dos deben dar lo mismo.
- **números → dominio:** DIR-03 (con `sin_objetivo: true`), ENT-01 y DIR-DEC14 se calculan en `Chequeo`/`KPIEvaluador`
  desde las fichas, con la misma regla que `Invariantes`. No leo `Invariantes.atenciones()` ni la bandeja todavía para no
  depender de una API a medias; en la integración se puede cambiar (las pruebas de números fijan el resultado esperado).
- **números → hoy-decisiones (pantallas):** Hoy sale de un `PanelMetricas` por `sesion.revision`: `frase(decisiones:)`
  (con `bandeja.pendientes`), `foco` (siempre uno: es el único destacado violeta), «Pide tu decisión» de la bandeja del
  dominio, `semana` (barra de horas frente al `tope` y `aviso` con icono y texto), «Lo que cabe hoy» = `semana.diaDeHoy`,
  **Alertas solo si `!alertas.isEmpty`**, y `lineaMika()`. Lo que la persona decide sobre una tarjeta (posponer,
  descartar, resolver) va en `EstadoTarjeta` guardado **fuera** de la carpeta (estado de la empresa) y se pasa en
  `estados:`; el historial, en `historial:`. Nada de eso se escribe en la carpeta.
- **números → andamio:** `NumerosDelNucleo` usa bien la API (`FotoMetricas`, `KPIEvaluador`, `EtapaCalculador`); la firma
  no cambia. Para la cabecera, `PanelMetricas.ritmo(area)` (`RitmoArea`) ya es «el del número más atrasado», con
  objetivos incluidos; para el mapa 6×6 y el cuello, `panel.mapa`; para Sistemas y activos, `EtapaArea.sistemas`.
- **números → integración (plantilla de Metas, rol funciones de F1):** `Recursos/Plantillas/1 · Dirección/Metas.md` da a
  cuatro códigos un sentido distinto del de Ribera y `kpi.json`: VEN-WON («Ganadas sobre cerradas» frente a «Ventas
  cobradas del mes»), FIN-AR («Cobrado en plazo» frente a «Cobros vencidos»), EQU-HEALTH («Piezas sin señal» frente a
  «Agentes sanos») y EQU-COST («Uso frente al tope» frente a «Coste de agentes del mes»). El evaluador calcula por código
  con el sentido de `kpi.json`. Hay que alinear la plantilla con el catálogo (propuesta) o cambiar los códigos.
- **números → diccionario (SISTEMAS §1.5) y `config.yaml`:** lo que leen las métricas además de lo ya escrito:
  `ultimo_toque` (oportunidad; si no está, la última fecha de «## Seguimiento», la de aceptación o la de creación),
  `estimacion_h` (tarea), `sin_objetivo` (proyecto), `ocupante` (rol), `evidencia_url` (contenido publicado), y en
  `.tls/config.yaml`: `capacidades:` (`declarada`, `ejecutor`, `desde`), `titular:`, `agenda.tope_horas_dia`,
  `agenda.zona` y `avisos.tope_tarjetas_dia`. En la bitácora, `· VEN-08 ·` (la función) y `uso 0,04 USD`.
- **números → `Package.swift` (hecho, 23/10):** recursos de TLSCore: `.copy("Recursos/Programa")` junto a las plantillas.
- **areas-a → TLSCore (hecho, 23/10; carpeta nueva propia `Sources/TLSCore/AreasA/`):** `LoteDeTareas` (público, envuelve
  `TareasEnLote` del dominio, que es interno: el plan de 4 semanas crea sus tareas en un solo plan), `PortalDocumento` /
  `PortalCliente` y `RegistroIncidencias` / `CuentaAtras` / `HorasHabiles`. Están en el núcleo para que los números puedan
  usarlos. Si el dominio prefiere tenerlos en `Dominio/`, se mueven sin cambiar la API.
- **areas-a → números:** ENT-INC («incidencias fuera de plazo») ya se puede calcular: `RegistroIncidencias.leer` de cada
  `Proyectos/*/Incidencias.md` y `fueraDePlazo(ahora:zona:)` («Sin dato» si no hay ningún registro). Hoy lo cuenta la
  Operación de Entrega; Control y Hoy siguen diciendo «Sin dato» hasta que `KPIEvaluador` lo adopte. Igual ENT-ARR48: el
  Viaje está en `PortalDocumento.sesiones` (la primera sesión agendada).
- **areas-a → números/dominio:** horas hábiles = de lunes a viernes, el día entero, sin festivos (decisión del rol: el
  PLAN no lo detalla). Si se quiere jornada (p. ej. 9–18) o calendario de festivos, se cambia solo `HorasHabiles`.
- **areas-a → integración (F1, `Fichas/`):** la ficha de proyecto de F1 enseña la pestaña «Viaje» con la sección
  `## Viaje` de `Proyecto.md`; el PLAN (§4.4) y la plantilla ponen el Viaje en `Portal.md`. La Operación de Entrega lee
  `Portal.md` (en la carpeta del proyecto o en `3 · Entrega/Portal Cliente/<slug>/`) y, si no hay, el `## Viaje` de la
  ficha. Convendría que la ficha haga lo mismo (`PortalDocumento.leer`).
- **areas-a → dominio:** «Plan de 4 semanas para el cuello» crea hoy **tareas** (una por semana, en las tareas del área
  del cuello). SISTEMAS DI3 dice «como proyecto interno»: la plantilla `plan-de-4-semanas` pide la pregunta `cuello` y
  `{{diagnostico.enlace}}`, y las tareas de un proyecto que aún no existe no se pueden enlazar con `TareasEnLote`. Si se
  quiere el proyecto, haría falta que el lote acepte un proyecto creado en el mismo plan.
- **areas-a → pendiente (Ventas):** «Preparar propuesta» (precio copiado de `Oferta.md`, `Invariantes.precioDeOferta`)
  no está en esta pantalla: la acción rápida de la cabecera es del andamio y la propuesta se crea hoy desde la ficha de la
  oportunidad (F1).
- **hoy-decisiones → andamio (Shell, sin dueño en la fase de pantallas):** la insignia de Decisiones la pone
  `AlmacenHoy` en cuanto se pinta Hoy, Decisiones o el Resumen de un área (y desde entonces se mantiene sola). Si la
  ventana se restaura en otra pantalla, la insignia no sale hasta entonces: al abrir la empresa (`ContenidoEmpresa`),
  llamar una vez a `Task { await AlmacenHoy.de(sesion).actualizar() }`. Se suelta solo (referencia débil a la sesión).
- **hoy-decisiones → dominio:** `TarjetaDecision.problema` y `porque` llegan con el Markdown de los enlaces
  («[Jorge Martín](../..)»); las pantallas lo pasan por `LinkParser.plainText`. Podría darlo ya en texto (y los enlaces
  como evidencias). `RegistroDecisiones.limpio` cambia « · » por «, » también dentro del texto de un enlace: el origen se
  escribe «Título (T-0001)», sin « · ». La bandeja no sabe de posposiciones: se guardan fuera de la carpeta (`hoy.json`) y
  se filtran en `DatosHoy`; si el dominio quiere contarlas (DIR-DEC14), que lo diga.
- **hoy-decisiones → números:** `KPIEvaluador.area(deCodigo:)` es interno; para «Fijar el umbral» uso el prefijo del código
  (`AreaCode(rawValue: "VEN")`). Las citas del Calendario (F5) entrarán por `PanelMetricas.calcular(eventos:)`: `DatosHoy`
  aún no las pasa.
- **hoy-decisiones → todos (hecho):** `FlujoChips` (filas de chips que saltan de línea) es el de
  `Relaciones/ConectadoConVista.swift` (F1); Hoy y Decisiones lo usan. No volver a declararlo.
- **hoy-decisiones → integración (F1, `Fichas/AlmacenRelaciones.swift`):** `actualizar()` puede quedarse dando vueltas
  en el hilo principal si dos llamadas coinciden y la foto no llega (`instantanea()` sin carpeta, o tras `soltar` al
  cerrar la empresa): la segunda espera a `carga`, que ya terminó sin poner `revisionCargada`, y vuelve a empezar sin
  soltar el hilo. Lo vi en las pruebas (una sesión cerrada con Hoy aún vigilando). `AlmacenHoy` ya no llama con la
  empresa cerrada y pone sus cargas en fila, pero convendría que `actualizar()` ponga `carga = nil` dentro de la tarea o
  salga si la foto vuelve vacía.
- **hoy-decisiones → integración:** «Cobros por confirmar» lleva a `.banco(nil)`: confirmar es allí, siempre con el clic
  de la persona (Hoy no confirma nada). «Marcar hecha» del foco escribe por `escribirConDominio`.

- **tareas → navegación (hecho, 23/10; excepción de §3):** `Navegacion/Destino.swift`, `Destino.para`: `if tipo == .task
  { return .tarea(ruta) }` (y su comentario en `case tarea`); `RecorridoF1Tests`: las migas acaban en `.tarea(tarea)`.
- **tareas → integración (Revisar):** las tarjetas de las tareas (`Tareas.md` heredados, Adoptar, números repetidos,
  tareas movidas en Finder) salen hoy en Tareas. Para que estén también en «Revisar» basta una línea en
  `Pantallas/RevisarPantalla.swift`, tras las tarjetas de conflictos: `RevisarTareas(sesion: sesion)` (trae su modelo y se
  pinta solo si hay algo). Si se quiere que Hoy enseñe «Revisar» por ellas, `sesion.hayQueRevisar` tendría que contarlas
  (`RevisionTareas.de(foto).hayAlgo`).
- **tareas → núcleo (funciones de F1, `TaskStore`):** `cambiarEstado(soloEstado: true)` no apunta nada en la Actividad;
  el criterio y esta tarea piden «solo `estado`» **y** su entrada. Lo hace `PlanesTarea.cambiarSoloEstado` (TLSUI) con
  `anadirActividad`; lo limpio sería una opción en `TaskStore` (`soloEstado` + actividad) para que el tablero del proyecto
  (`Fichas/TableroProyecto.swift`, que hoy no lo apunta) haga lo mismo.
- **tareas → núcleo:** `LegacyTasksMigrator.encontrar()`/`proponerTodos` y `TaskStore.duplicados()` incluyen lo privado;
  aquí se filtra antes (`RevisionTareas`), pero conviene filtrarlo en el núcleo. `Tarea` no trae `estimacion_h`,
  `dedicadas_h`, `bloqueada_por` ni `capacidad` (se leen del frontmatter aparte). `CodeFence` y
  `MarkdownSections.heading` son internos: `ActividadDeTarea` lleva su propio lector mínimo de encabezados y bloques.
- **tareas → fichas (F1):** el tablero del proyecto abre las tareas con `.ficha` («Abrir como ficha», ↩, doble clic) y
  su `ActividadTarea` no traduce los eventos; si se quiere lo mismo que en Tareas, `navegar(.tarea(ruta))` y
  `ActividadDeTareaVista`/`ActividadDeTarea.leer`. `Responsables.opciones` mira también las fichas privadas al proponer
  responsables: `ResponsablesTarea.opciones` es la misma lista sin ellas.
- **tareas → diccionario (SISTEMAS §1.5):** en `tls:evento` de la Actividad: `"menciones"` (identificadores separados por
  comas) en los comentarios con @, y `"desde":"tablero"` en los cambios de estado del tablero.
- **tareas → F4 (asistentes):** las menciones quedan en el evento del comentario para que `TaskQueue` las dispare;
  `EstadoAsistenteTarea.de(…, enMarcha:)` recibe de la ejecución si el asistente está trabajando; «Empezar ahora» en una
  tarea de asistente deja Por hacer con `planificada: hoy` (PLAN §4.2).

- **areas-b → andamio/dominio (Deshacer de una cadena):** `escribirConDominio` deja en Deshacer solo el plan de la persona.
  Si después escriben reglas (confirmar el cobro de Talleres Martín → Ganada, proyecto y sus tareas), ⌘Z y el «Deshacer»
  del aviso dicen «Antes hay que deshacer «…», que es más reciente» y la confirmación no se puede deshacer desde la app.
  Propuesta para `Shell/DominioEmpresa.swift`: registrar un Deshacer de la cadena (los planes de `ResultadoDominio.reglas`
  `.hecho`/`.tareaParaPersona` en orden inverso y luego el de la persona). Las pruebas de areas-b solo comprueban Deshacer
  en lo que no dispara reglas (importar, ignorar, un pago, Marca, `Metas.md`).
- **areas-b → integración (plantilla de Metas, F1):** PLAN §6.5 pide FIN-RUNWAY en Control con meta 3 y alerta 1, pero
  `Recursos/Plantillas/1 · Dirección/Metas.md` no tiene su fila. Finanzas › Caja lo cubre con «Medirlo en Control» (añade
  la fila sin meta, con la propuesta en «Por qué»); lo limpio es que la plantilla traiga `| FIN-RUNWAY | Meses de caja | |
  | Propuesta: meta 3 meses, alerta 1 mes |`. Ribera dice 3 meses y alerta 2 meses: se respeta.
- **areas-b → números/banco:** Finanzas › Caja enseña el número de meses de `FilaControl` (KPIEvaluador) y la salida media
  de `Tesoreria` solo sin número clave: hoy difieren en un céntimo (3.393,52 € frente a 3.393,51 €) y en «mes cubierto
  entero» (ya anotado por números). Al unificarlos, el pie puede volver a decir la salida media.
- **areas-b → diccionario (SISTEMAS §1.5):** la tarea de «Proponer a Ventas» lleva `conversacion: "[[…]]"` y
  `origen: manual`; la conversación pasa a `estado: Propuesta a Ventas` (plantilla «Conversación»). Las piezas usan
  `publicar` (calendario) y `publicado` (al pasar a Publicado, hoy si faltaba). Las rutinas sin ficha se reconocen por la
  carpeta de sus registros (`Rutinas/dia`, `Rutinas/semana`, como en Ribera).
- **areas-b → banco:** «Ignorar…» ofrece cinco motivos fijos («Sin factura: impuestos», «… nómina o seguros sociales»,
  «Traspaso entre cuentas propias», «Retirada del titular», «Sin factura: otro gasto»); si el banco quiere sus propias
  naturalezas al ignorar, `planIgnorar` podría recibirlas.
