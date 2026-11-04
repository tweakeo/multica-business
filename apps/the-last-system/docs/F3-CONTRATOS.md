# F3 · Contratos entre roles («Puesta en marcha»)

F3 = PLAN §9 F3 (10 criterios), con §6.7 (puesta en marcha), §6.8 (tutorial y manual), §4.1–§4.7 (formato que se
escribe) y §8 (seguridad), más la propuesta v2 (`docs/propuesta/SISTEMAS.md`, `PLANTILLAS.md`,
`DISENO-MOSAICO-V2.md`, `REQUISITOS-ADICIONALES.md`, `VIDEOS.md`), que manda donde difieran. Lo de antes sigue en
`docs/F0-CONTRATOS.md`, `docs/F1-CONTRATOS.md`, `docs/F1-INTERFAZ-CONTRATOS.md` y `docs/F2-CONTRATOS.md`: aquí solo
se añade. Como siempre, las firmas se pueden **ampliar**, no cambiar; un cambio se pide en «Cambios pedidos» (al
final, una sección por rol).

Reglas que no se rompen (resumen):
1. **Nada se escribe antes de «Aplicar»** (F3-1): cada paso prepara un `WritePlan` y su vista previa; solo «Aplicar»
   lo ejecuta por `CommandBus`, como la persona. Todo se deshace. Nunca se borra nada (retirar = `Archivo/`).
   Importar nunca sobrescribe y verifica por recuento y SHA-256.
2. La carpeta real (`clase: real`) solo se lee. Nunca se descarga nada de iCloud al recorrer.
3. Lo privado nunca se copia, no se clasifica con IA ni se enseña. En pruebas, nombres neutros (`Expediente privado`).
4. La IA (Claude Code de la persona, por TLSAgents, en el sandbox) es opcional y con consentimiento; sin ella todo
   funciona con reglas fijas. En pruebas, un ejecutable falso.
5. Sin dependencias nuevas; español de España sin jerga (lint del glosario); accesibilidad como en F1/F2. Cada paso en
   2–3 líneas, respuestas premarcadas con su origen, «No lo sé» siempre (se escribe PENDIENTE), «Seguir más tarde» y
   «Quedan ~N min» siempre visibles.

## 1. Propiedad de ficheros

### 1.1 Fase de núcleo

| Rol | Ficheros |
|---|---|
| motor | `Sources/TLSCore/PuestaEnMarcha/**`, target `TLSOnboarding` en `Package.swift` (y su producto y su target de pruebas), `Sources/TLSOnboarding/**` (solo andamio y huecos), este documento, `Tests/TLSCoreTests/PuestaEnMarcha/**`, `Tests/TLSOnboardingTests/**` |
| importador | `Sources/TLSImport/Importar/**` (y lo que ya hay en TLSImport si se amplía sin romper su API), sus pruebas |
| tutorial | `Sources/TLSUI/Tutorial/**`, `Sources/TLSUI/Manual/**`, `Sources/TLSDesign/Componentes/Tutorial*.swift` (ancla `.tutorialAnchor`), `Sources/TLSImport/Multica/**`, `App/Recursos/Manual/**` y, solo para añadir `.tutorialAnchor(...)`, una línea en las pantallas de TLSUI |

### 1.2 Fase de pantallas

| Rol | Ficheros |
|---|---|
| pasos | `Sources/TLSOnboarding/**` salvo `Ordenar*` |
| ordenar | `Sources/TLSOnboarding/Ordenar*/**` y `Sources/TLSUI/Importar/**` |

En la fase de pantallas **nadie** toca `TLSCore`, `Package.swift`, `TLSDesign` ni `TLSUI` fuera de lo dicho: lo que haga
falta se pide abajo. `Sources/TLSOnboarding/Motor/LanzadorClaudeCode.swift` y `ModeloPuesta.swift` los hizo el motor y se
usan tal cual (se pueden ampliar, no cambiar sus firmas). El target de pruebas `TLSOnboardingTests` ya existe.

## 2. El motor de la puesta en marcha (rol motor: `Sources/TLSCore/PuestaEnMarcha/**`)

PLAN §6.7 entero. Todo es un valor (`OnboardingEngine`, `Sendable`) que **solo lee** la carpeta; guarda su estado en
`onboarding.json` (Application Support) tras cada respuesta y solo escribe en la carpeta con «Aplicar»
(`AplicadorPuesta`, por `CommandBus`, como la persona). Sin Claude todo funciona (premarcado y entrevistador con reglas
fijas). Probado en `Tests/TLSCoreTests/PuestaEnMarcha/` (27 pruebas con las de TLSOnboarding).

### 2.1 Tipos

- `PasoPuesta` (`bienvenida`, `alcance`, `conocer`, `ordenar`, `organizar`, `sinTi`, `diaADia`, `numeros`, `conectar`,
  `recorrido`; `numeroTabla` «0»…«8», `titulo`, `escribeEnLaCarpeta`: no escriben `alcance`, `conectar` ni `recorrido`).
- `RutaPuesta`: `copiaG3` (carpeta organizada: tope **15** pantallas), `carpetaPorOrdenar` (tope 40, con las de
  ordenar), `empresaNueva` (tope **40**), `ejemplo` (1 pantalla); `topePantallas`, `titulo`, `conCarpeta`.
  `AlcancePuesta` (`proceso`, `area`, `todo`). `EstadoAreaPuesta` (`activa`, `preparada`, `en reposo`).
- Respuestas: `ValorRespuesta` (`texto`, `opcion`, `opciones`, `escala`, `siNo`, `numero`, `rutas`, **`noLoSe`**),
  `OrigenRespuesta` (`persona` · `carpeta(ruta)` «Lo saqué de Rumbo.md» · `propuesta(texto)` · `asistente`),
  `Respuesta` (`valor`, `origen`, `confirmada`, `repreguntada`, `fecha`, `vieneSinCambiosDeLaCarpeta`).
- Preguntas: `PreguntaID` (texto estable, p. ej. `conocer.VEN.funciona`; constantes y constructores
  `PreguntaID.como`, `.funciona(.ventas)`, `.sistema("VE1")`, `.montado("FIN-1")`, `.meta(.finanzas)`, `.conexion(.mail)`…),
  `Pregunta` (`texto`, `ayuda`, `tipo: TipoPregunta`, `admiteNoLoSe` —siempre, salvo «¿Cómo empiezas?», «¿Cómo quieres
  trabajar con ella?», la carpeta elegida y las privadas—, `obligatoria` —las privadas—, `repregunta`, `premarcada`,
  `referencia` «En Rumbo.md pone: …», `esOpcional`), `TipoPregunta` (`eleccion`, `escala`, `siNo`, `textoCorto`,
  `textoLibre` —en su propia pantalla—, `cifra(unidad:sinMeta:)`, `hora`, `rutas(carpetas:varias:)`), `OpcionPregunta`,
  `TextosPuesta` (dolores, metas, etapas por área; `llano(_:)` quita la jerga de los nombres del estándar),
  `SistemaCatalogo` (los 19 de SISTEMAS §2.5 con su código, área, alias de G3, `seInstala` —de serie o base— y número),
  `NumerosDeSerie` (el número que se propone por área y los que se pueden elegir), `ConexionPuesta` (las 7 filas del
  paso 7), `HitoRecorrido` (los 5 del paso 8; `aprobarPropuesta` «llega con los asistentes»).
- Pantallas: `Pantalla` (`id` estable, `paso`, `tipo: TipoPantalla` —`eleccion`, `formulario`, `textoLibre`, `resumen`,
  `vistaPrevia`, `delegada` (las del paso 2), `informativa`—, `titulo`, `explicacion` de 2–3 líneas, `preguntas`,
  `area`, `conVistaPrevia`, `aplicaAqui`, `minutos`). Regla: si un paso tiene una sola pantalla de preguntas, su vista
  previa y «Aplicar» van en ella; si tiene más, en una pantalla aparte al final. En la ruta de la copia de G3, Conocer,
  Organizar, Qué funciona sin ti y Tus números son **una** pantalla de resumen premarcado cada uno.
- Estado: `EstadoPuestaEnMarcha` (`Codable`; `vault_id`, `ruta`, `persona`, `pantalla`, `respuestas`, `pasos`
  (`EstadoPaso`: `pendiente|aplicado|omitido`, `plan` para Deshacer, `resumen`), `ordenar` (`ResumenOrdenar`), `recorrido`
  (hitos), `usar_asistente`, `en_pausa`, `permiso_denegado`, fechas). Lee ficheros a los que les falten claves.
  `AlmacenPuesta(vaultID:appSupport:)`: `url` = `<appSupport>/<id>/onboarding.json` (0700/0600, nunca en iCloud Drive),
  `leer()`, `guardar(_:)`, `retirar()`, `pendientes(appSupport:)` (sin terminar, la más reciente primero).
- `ContextoCarpeta(foto:entrada:reloj:catalogo:)` / `.leer(root, entrada:)` / `.vacio()`: lo que ya sabe la carpeta
  (solo lee; nada privado): `organizada`, `rutaDetectada`, `areas` (`AreaReader`), `etapas` (`EtapaCalculador`, lo
  declarado), `nombreEmpresa`, `sistemasConFicha`, `servicios`, `logo`, `nombresPrivados`, `base90Dias(_:)`,
  `premarcada(_ id)`, `referencia(_ id)`. Lo caro se calcula una vez por foto.

### 2.2 `OnboardingEngine`

- Abrir: `OnboardingEngine.abrir(vaultID:contexto:almacen:persona:entrevista:)` (retoma si hay `onboarding.json`; quita
  la pausa) o `init(estado:contexto:almacen:entrevista:)`. `cambiarContexto(_:)` al elegir, copiar u ordenar la carpeta.
- Ruta y alcance: `ruta`, `soloMirar` («Ver sin tocar»: no hay más pasos), `alcance`, `procesoElegido`,
  `areasDelAlcance`, `areasConDetalle` (activas o preparadas), `areasActivas`, `sistemasSinTi` (del estándar, `14-calibracion`),
  `pasosIncluidos` (un proceso: sin Conocer, Ordenar ni Día a día).
- Pantallas: `pantallas`, `pantallas(de:)`, `pantallaActual`, `indiceActual`, `preguntas(de:)`, `preguntasActuales`
  (las condicionadas solo si toca: las de etapa se paran en el primer «no»), `pregunta(_ id)` (con premarcado),
  `valor(_ id)`, `respuesta(_ id)`, `faltan`.
- Contestar (guarda tras cada una): `responder(_:_:) async -> ResultadoRespuesta` (`.guardada` | `.repreguntar(texto)`,
  una sola vez por pregunta; lo premarcado contestado igual conserva su origen), `noLoSe(_:)`, `confirmarPremarcadas()`,
  `usarAsistente(_:)`.
- Navegar: `siguiente() -> ResultadoAvance` (`.pantalla(p)` | `.faltan(ids)` | `.faltaAplicar(paso)` | `.terminada`;
  confirma lo premarcado; los pasos que no escriben se dan por hechos al dejarlos), `anterior()`, `ir(a:)`,
  `omitir(_:)`, `seguirMasTarde()`.
- Contadores: `quedanMinutos` («Quedan ~N min», desde la pantalla actual), `progreso: ProgresoPuestaEnMarcha`
  (`paso`, `numero`, `total` —el 0b cuenta con el 0—, `texto` «Seguir con la puesta en marcha · paso 4 de 9»,
  `textoMinutos`, `terminada`, `enPausa`; `ProgresoPuestaEnMarcha.leer(vaultID:appSupport:)`).
- Vista previa y aplicar: `vistaPrevia(_ paso) throws -> VistaPreviaPaso`; `aplicar(_ vista, bus:) async throws`
  (escribe y marca el paso con su plan), `aplicarEmpezarDeCero(_ vista, empresas:registro:appSupport:)` (paso 0 sin
  carpeta: la crea en `~/The Last System/Empresas/`, la registra con el `vaultID` de la puesta en marcha y escribe),
  `deshacer(_ paso, bus:)` (si su plan es lo último escrito; si no, `ErrorPuesta.otroPlanDespues`), `marcarAplicado`,
  `marcarDeshecho`.
- Lo de otros roles: `registrarCopia(_ entrada, root:appSupport:)` (tras `DemoCopier`: el estado pasa a la carpeta nueva
  y la ruta queda fijada), `registrarOrdenar(_ ResumenOrdenar, aplicado:)` (el importador: sus pantallas cuentan para el
  tope y «Quedan ~N min»; sus planes, para Deshacer), `permisoDenegado(_:)` (sale la pantalla de recuperación),
  `marcarHito(_:)` (el tutorial).
- `OnboardingEngine.ejemploCompletado(contexto:vaultID:persona:almacen:)`: Ribera con la puesta en marcha hecha y todas
  las respuestas confirmadas desde la carpeta, para repasarla paso a paso.

### 2.3 Qué escribe cada paso al «Aplicar» (`VistaPreviaPaso`)

`VistaPreviaPaso`: `paso`, `plan: WritePlan?` (`nil` = nada que escribir; todo o nada, un solo Deshacer), `cambios:
[CambioPrevisto]` (`ruta`, `clase` crear · cambiar · copiar, `antes`, `despues` —**exactamente** lo que quedará escrito,
probado fichero a fichero—, `lineasCambiadas`, `resumen`), `resumen` («Crear 9 · Cambiar 2 · No se borra nada»),
`avisos`, `entendido: LoQueHeEntendido?` (paso 1: `filas` con funciona, depende, etapa, dolor, meta y cita; `cuello`;
`porQue`; `etapaGlobal`), `fueraDeLaCarpeta`. Cada fichero se escribe con compare-and-swap sobre los bytes leídos
(`WriteOp.replaceText`) o se crea sin pisar; si un nombre nuevo ya existe en otra carpeta, los enlaces se protegen en el
mismo plan (`LinkRefactor.protegerEnlaces`). **Lo que llega premarcado de la carpeta y no se cambia no se reescribe.**
«No lo sé» se escribe `PENDIENTE` donde iba la respuesta (celda, sección, propiedad, línea en «## Pendiente» o
`declarada: PENDIENTE`). Lo privado nunca se toca.

| Paso | Escribe |
|---|---|
| 0 (de cero) | `Empresa.md` (plantilla «Tu empresa», `titular`), `AGENTS.md`, `.tls/layout.json` (`humana`), `.tls/config.yaml` (`version`, `id`, `clase: copia`, `creada`, `privado: []`) y las 6 `Área.md` (cabecera v2, sin `estado`: se decide en Organizar) |
| 0 (con carpeta) | Nada en la carpeta: la copia la hace `DemoCopier` y se registra con `registrarCopia` |
| 1 | `1 · Dirección/Diagnóstico.md` (`etapa_global`, `cuello`, `## Encuadre`, frase del negocio con sus 5 huecos, frase destino literal, la tabla de las seis áreas, el cuello y síntoma, causa y pieza que falta) y, si lo dijo la persona, «Qué es la empresa» y «Adónde vamos» de `Rumbo.md` |
| 3 | `Área.md` (`estado`, `ocupante`, `rol`, la tabla `\| Código \| Sistema \| Estado \|` —en G3 se conserva la lista y se añade la tabla con los nuevos—), los roles que faltan en `6 · Equipo/Roles/`, esqueletos de los sistemas de serie y base que faltan (ficha de sistema v2), `Empresa.md` (`areas_activas` y la columna Estado), `AGENTS.md` (`## Áreas activas`), servicios y `Productos/Oferta.md` (hasta 3 ofertas y `## Embudo`), el plan de entrega, el logo («Ya lo tengo»: copia a `5 · Marca/Activos/Logo/original/` y `logo:` en `Marca.md`; «Está en mi web» y «Aún no tengo»: una tarea en Marca) y `vocabulario:` en `.tls/config.yaml` |
| 4 | `capacidades:` en `.tls/config.yaml` (las del sistema, de `14-calibracion`: `declarada`, `ejecutor` H/IA/A/S, `declarada_por`, `desde`; «Sí» a dejarlo a un asistente: `modo: supervisado`, ejecutor IA) y una tarea «Revisar lo que dejaste a los asistentes» planificada a los 7 días (laborable) |
| 5 | `1 · Dirección/Rutinas/revision-de-la-semana.md` (o la semanal que ya hubiera) y `agenda.tope_horas_dia` en `.tls/config.yaml` |
| 6 | Solo las celdas Meta y Alerta de `Metas.md` (la fila del número se añade si falta, sin tocar las demás; `numero_clave` en `Área.md` si se eligió otro) y, si se pidió, `1 · Dirección/Objetivos/facturacion-tN-aaaa.md` |
| 0b, 2, 7, 8 | Nada (2 lo escribe el importador; 7 y 8 solo `onboarding.json`) |

Propuestas del paso 6: la meta es 1,2 × lo de los últimos 90 días (`base90Dias`, marcada «Propuesto»), si hubo algo;
si no, la de la columna «Por qué» de `Metas.md`; lo decidido en `Metas.md` manda (origen carpeta).

### 2.4 Entrevistador

`InterviewEngine(lanzador:)`: `valorar(_ pregunta, respuesta:conAsistente:privado:) async -> ResultadoEntrevista`
(`.aceptar` | `.repreguntar(texto)`). Sin asistente o si falla, `InterviewEngine.determinista` (corta, palabras vacías,
frase destino sin un número). Con asistente: `LanzadorEntrevista` (protocolo: `pedir(_ mensaje, esquema:)`) con
`InterviewEngine.esquemaJSON` (`{vaga, repregunta}`); solo si la persona consintió (`usarAsistente`) y nunca si la respuesta
nombra algo privado. En TLSOnboarding, `LanzadorClaudeCode(probe:estado:negadas:modelo:presupuestoUSD:tiempo:)` lanza
`claude -p --json-schema --no-session-persistence` con `ClaudeProbe` (sandbox de los asistentes, sin servidores ni
herramientas; lee `structured_output` o `result`). Probado con un ejecutable falso dentro del sandbox. También es el
`EjecutorClasificacion` de `AIClassifier` (TLSImport, paso 2): `ejecutar(peticion:esquema:)`, con el mismo consentimiento.

### 2.5 Abrirla desde el arranque y desde Hoy (sin que TLSUI dependa de TLSOnboarding)

- `PuertaPuestaEnMarcha.ventanaID` (`"puesta-en-marcha"`) y `PeticionPuestaEnMarcha(modo: .empezar | .retomar | .repasar,
  vaultID:)` (`Codable`, `Hashable`): TLSUI abre la ventana con `openWindow(id: PuertaPuestaEnMarcha.ventanaID, value:
  peticion)`. La escena la declara la app con `OnboardingEscena()` (TLSOnboarding).
- Hoy: `PuertaPuestaEnMarcha.avisoDeHoy(vaultID:)` → `ProgresoPuestaEnMarcha?` (`nil` si no hay nada que seguir);
  `texto` «Seguir con la puesta en marcha · paso 4 de 9» y `textoMinutos` «Quedan ~N min».
- Arranque: `AlmacenPuesta.pendientes()` (también las de «Empiezo de cero» sin aplicar, que aún no tienen carpeta).

## 3. Huecos de TLSOnboarding: el `init` es contrato

Empiezan con `// HUECO (andamio F3) · rol …` y dicen qué falta. Compilan y enseñan lo verdadero del motor (la pantalla,
sus preguntas con el origen de lo premarcado, «No lo sé», el resumen de la vista previa). **Se rehace el cuerpo, no la
firma.**

| Tipo (fichero) | `init` | Rol |
|---|---|---|
| `OnboardingEscena` (`OnboardingFlujo.swift`) | `init()` · `WindowGroup(id: PuertaPuestaEnMarcha.ventanaID, for: PeticionPuestaEnMarcha.self)` | pasos |
| `OnboardingVentana` (mismo fichero) | `init(peticion: PeticionPuestaEnMarcha)` | pasos |
| `OnboardingFlujo` (mismo fichero) | `init(modelo: ModeloPuesta)` | pasos |
| `PasoBienvenida`, `PasoAlcance`, `PasoConocer`, `PasoOrganizar`, `PasoSinTi`, `PasoDiaADia`, `PasoNumeros`, `PasoConectar`, `PasoRecorrido` (`Pasos/Paso*.swift`) | `init(modelo: ModeloPuesta)` | pasos |
| `PasoOrdenar` (`Ordenar/PasoOrdenar.swift`) | `init(modelo: ModeloPuesta)` | ordenar |

`ModeloPuesta` (`@MainActor @Observable`, `ModeloPuesta.swift`): `init(motor:)`, `init(peticion:registro:appSupport:persona:)`;
`motor`, `pantalla`, `preguntas`, `progreso`, `ruta`, `pantallas`, `vista`, `repreguntas`, `error`, `trabajando`, `faltan`;
`responder(_:_:) async`, `noLoSe(_:)`, `siguiente()`, `anterior()`, `seguirMasTarde()`, `prepararVistaPrevia()`,
`aplicar(bus:) async`, `aplicarEmpezarDeCero(empresas:registro:appSupport:) async -> VaultEntry?`,
`deshacer(_:bus:) async`, `actualizar(_ cambio: (inout OnboardingEngine) -> Void)` (para `registrarCopia`,
`registrarOrdenar`, `marcarHito`…). (`HuecoPaso`, el cuerpo común provisional, ya no existe: cada paso tiene su pantalla.)

Identificadores de accesibilidad ya puestos: `puesta.flujo`, `puesta.seguirMasTarde`, `puesta.siguiente`,
`puesta.vistaPrevia`, `puesta.paso.<paso>`, `puesta.pregunta.<id>` (para el UI test que cuenta pantallas, F3-2).

## Tutorial, manual e importar de Multica (rol tutorial)

PLAN §6.8 y §9 F3. Nada de esto escribe en la carpeta salvo «Importar» de Multica (un plan, como la persona, con
Deshacer). El tutorial solo lee lo que cambió y guarda su avance en `Application Support/The Last System/tutorial.json`.

### Anclas y velo (`TLSDesign/Componentes/Tutorial*.swift`)

- `.tutorialAnchor(_ id: TutorialAnclaID)`: una línea en cada pantalla. No cambia la vista: pone detrás una sonda de AppKit
  (sin clics ni VoiceOver) que sabe dónde está en su ventana, así el hueco sale bien aunque la vista esté en otra columna
  o dentro de un desplazamiento. `TutorialAnclaID` es un texto (`"hoy.foco"`); las del tutorial están en
  `TLSUI/Tutorial/HitosTutorial.swift` (`.hoyFoco`, `.decisionesGrupo`, `.ventasCRM`, `.tareasNueva`, `.ficha`,
  `.direccionRegistrarDecision`, `.direccionMapa`, `.bancoImportar`, `.areaPestanas`).
- `TutorialAnclas.compartidas` (`@MainActor @Observable`): `version` (sube al aparecer, irse o moverse un ancla),
  `presentes(en:)`, `rectangulo(_:respectoA:)`, `contiene(_:punto:en:)`, `movida()`.
- `TutorialCapa(paso: TutorialPasoVisible?, alPulsar: (String) -> Void)`: velo `TLSPaleta.velo` con hueco (regla par-impar;
  fuera del hueco no se puede pulsar si `bloquearFuera`), anillo azul noche de 2 pt y burbuja. Sin ancla en pantalla: solo
  la burbuja, abajo a la derecha, sin velo. Anuncio para VoiceOver en cada paso (`TutorialAnuncio.anunciar`).
  `TutorialBurbuja`, `TutorialPasoVisible` (`rotulo`, `titulo`, `texto`, `marca` `.porHacer|.hecho|.llegaConLosAsistentes`,
  `progreso` «N de M hitos · Quedan ~N min», `botones: [TutorialBoton]`, `items: [TutorialItem]`), `TutorialColocacion`.
  Sin atajos de teclado en la burbuja (↩ y Esc son del editor). Sin magenta.

### Tutorial (`TLSUI/Tutorial/`)

- Raíz: `.tutorialAnchor(.raiz, sesion:, nav:)` en `Shell/ContenidoEmpresa.swift` (una línea). Pone la capa y escucha
  navegación (`.area(x)` → `areaVista`), anclas (`direccion.mapa` → `mapaVisto`), escrituras (`sesion.revision`) y clics
  dentro del foco de Hoy (monitor local de AppKit, solo mientras el paso lo pide).
- `ControladorTutorial.de(sesion)`: uno por sesión. Una sesión con estado propio (`VaultSession(entry:estado:)`, las pruebas)
  guarda `tutorial.json` y `onboarding.json` junto a ese estado y **no empieza sola**: ninguna prueba toca el Application
  Support de verdad. En la app, el ejemplo empieza su recorrido solo la primera vez que se abre.
- `TutorialEvent` (público): `focoDeHoy`, `decisionResuelta`, `oportunidadMovida`, `tareaCreadaYAsignada`, `fichaEditada`,
  `vistaEnFinder`, `decisionRegistrada`, `extractoImportado`, `mapaVisto`, `areaVista`, `asistenteAbierto`,
  `asistentesPausados`, `asistentesReanudados`. Los deriva el tutorial de lo escrito (`DetectorHitos`, puro) y cualquiera
  puede mandarlos: `TutorialEventos.registrar(_:empresa:)`. Solo cuentan con el recorrido en marcha; «Siguiente» y
  «Saltar» nunca marcan nada.
- `HitoTutorial` (10): foco de Hoy, aprobar o modificar, mover una oportunidad, crear y asignar una tarea, editar y ver en
  Finder, registrar una decisión, importar un extracto, mapa y cuello, ⌘J y pausar/reanudar (estos dos, «Llega con los
  asistentes»: se explican y no cuentan para el total, 8).
- `TipoRecorrido`: `.ejemplo` («Conoce la app con un ejemplo», 12 pasos sobre Ribera) y `.tuEmpresa` («Recorrido con tu
  empresa», paso 8). Los pasos de `.tuEmpresa` llevan los `id` de `HitoRecorrido` del motor (`hoy`, `area-del-cuello`,
  `aprobar-propuesta`, `editar-ficha`, `ver-en-finder`) y, al cumplirse, se marcan también en `onboarding.json`
  (`EstadoPuestaEnMarcha.recorrido`) con `AlmacenPuesta`. El cuello sale del mapa (`DatosDireccion.calcular`).
- `TutorialEventos.empezar(_:empresa:)`: empieza un recorrido (si la empresa no está abierta, al abrirla).
  `TutorialEventos.estado(_:empresa:)`. `AlmacenTutorial` (`tutorial.json`: `{version, recorridos: {"ejemplo"|<vault-id>:
  {fase, paso, partes, hitos, actualizado}}}`).
- Ejemplo: al abrirlo se deja su `onboarding.json` hecho con `OnboardingEngine.ejemploCompletado` (si no existe).
  `EjemploTutorial.huellas(de:)` (SHA-256 por fichero, con la línea `id:` de `.tls/config.yaml` igualada) prueba F3-7;
  «Reiniciar ejemplo» desde la burbuja final cierra sus ventanas, usa `InstaladorEjemplo.reiniciar` (Papelera), vuelve a
  dejar la puesta en marcha hecha y el recorrido sin empezar. «Dame un extracto» deja un extracto de ejemplo (2 movimientos
  nuevos) en `Application Support/The Last System/tutorial/` y lo enseña en el Finder para arrastrarlo.
- `ControladorTutorial.repasarPuestaEnMarcha: ((VaultSession) -> Void)?`: si alguien lo pone, la burbuja final ofrece
  «Repasar la puesta en marcha».
- `ComandosAyuda(model:)`: menú Ayuda con «Manual de The Last System» (⌘?), «De dónde salen las ideas», «Conoce la app con
  un ejemplo» y «Recorrido con tu empresa».

### Manual (`TLSUI/Manual/`, `App/Recursos/Manual/`)

- `EscenaManual()`: `Window("Manual", id: "manual")` con búsqueda (sin tildes ni mayúsculas). `ManualNavegacion.compartida`
  (`abrir(_ seccion:)`, `seccion`, `busqueda`; `idVentana = "manual"`, `seccionIdeas = "ideas"`).
- `BotonSaberMas(seccion:)`: abre el manual en esa sección. Secciones: `empezar`, `hoy`, `areas`, `sistema`, `etapas`,
  `decidir`, `relaciones`, `tareas`, `ventas`, `banco`, `carpeta`, `privado`, `asistentes`, `palabras`; un «Saber más» por
  paso de la puesta en marcha: `paso-<PasoPuesta.rawValue>` (`paso-bienvenida`… `paso-recorrido`); las ideas: `ideas`,
  `idea-1-3-1`, `idea-entrevistador`, `idea-seguimiento`, `idea-transferencia`, `idea-una-coleccion`, `idea-otras`.
- `MANUAL-TLB.md` viaja copiado (una vez, ver `docs/PROCEDENCIA.md`) pero no se enseña en la v1 (PLAN §12). Para enseñarlo
  basta añadirlo a `ManualBiblioteca.ficheros`.

### Importar de Multica (`TLSImport/Multica/`, `TLSUI/Importar/ImportarMultica.swift`)

- `MulticaCLI.localizar()`: el programa en el PATH, en las carpetas habituales (`/opt/homebrew/bin`, `/usr/local/bin`,
  `~/.local/bin`, `~/bin`) o en `/Applications/Multica.app/Contents/Resources/app.asar.unpacked/resources/bin/multica`. No
  lo lanza.
- `OrdenMultica` (cerrado, solo listar): `.perfiles` (`profile list --output json`), `.espacios(perfil:json:)` (`--profile p
  workspace list [--output json]`), `.tareas(perfil:espacio:desde:limite:)` (`… issue list --output json --limit 100
  --offset N --fields identifier,title,description,status,status_category,priority,due_date,created_at`).
  `EjecutorMultica` (protocolo; en pruebas, falso) y `ProcesoMultica(cli:tiempoMaximo:)`. `ErrorMultica` en llano.
- `LectorMultica(ejecutor:)`: `perfiles()` (vacío si no sabe: se escribe a mano), `espacios(perfil:)` (JSON y, si no, la
  tabla de texto), `tareasAbiertas(perfil:espacio:)` (páginas de 100 con `has_more`; abiertas = todo menos `done` y
  `cancelled`). `LecturaMultica` acepta varias formas de JSON (`issues`/`data`/`items`, `has_more` arriba o en `meta`).
- `ImportadorMultica(snapshot:reloj:)`: `previa(_:) -> PreviaMultica` (marcadas salvo las personales —`ClasificadorPersonal`:
  salud, médico, pastilla, baja, IT en mayúsculas, FREMAP, mutua, iPhone, AirPods, personal…— y las ya importadas; área
  sugerida por `SugerenciaArea`) y `plan(_:carpetaPrivada:autor:) -> PlanImportacionMultica` (nada se escribe;
  `TaskStore.crear` por tarea, numeración seguida, `origen: importacion`, `fecha_corte`, estado backlog→Sin programar,
  todo→Por hacer, in_progress→En curso, in_review→En revisión, blocked→Bloqueada, prioridad Urgente/Alta/Media/Baja,
  `vence`, la descripción en «Descripción» con sus encabezados bajados a cuarto nivel y sus comentarios neutralizados,
  **`externo: ext:multica:<ID>`** y una entrada de Actividad con el mismo `externo`). Las personales marcadas van a
  `<carpeta privada>/Tareas/` (tiene que ser privada). `aplicar(_:con: CommandBus)` y `aplicar(_:con: MotorDeDominio)`
  (modo importación). Una segunda importación las ve como «Ya importada» (propiedad `externo` o la marca en el texto).
- `ImportarMulticaHoja(sesion:)`: perfil y espacio → vista previa con casillas, área por fila y carpeta privada → «Importar»
  (`sesion.escribir(plan:)` con `setModoImportacion(true)` mientras escribe). Un aviso «Importé N tareas de Multica» con
  Deshacer.

## Ordenar lo que tienes (rol importador: `Sources/TLSImport/Importar/**`)

PLAN §6.7 paso 2 y §9 F3 (criterios 1, 4 y 9). Todo lee hasta «Aplicar»; «Aplicar» es **un** `WritePlan` por
`CommandBus`, como la persona, que se deshace de una vez. Probado en `Tests/TLSImportTests/Importar/` (36 pruebas, con la
copia de G3 de la fixture y Ribera en temporales propios, Vision de verdad y un Claude falso).

**Flujo para la pantalla (rol ordenar):**
1. `InventarioImportacion.hacer([FuenteImportacion], opciones: .init(hoy:), fileSystem:, progreso:)`: la carpeta de la
   empresa (`FuenteImportacion.carpetaDeLaEmpresa(raiz, privado:exclusiones:)`, alias «Carpeta»: se **mueve** dentro) y
   las de fuera (`FuenteImportacion(alias:raiz:clase: .externa)`: se **copian**; el original no cambia). Hilo protegido
   (nada se descarga de iCloud), misma poda que la copia (lo privado de `.tls/`, lo elegido y lo oculto no se listan).
   `resumen` «312 ficheros · 310 solo en iCloud: los miro por su nombre», `porHerramienta`, `porTipo`, `soloEnICloud`.
   `ElementoInventario` (`clave` «alias/ruta», `herramienta`, `tipo`, `sha256`, `soloEnICloud`, `sensible` —claves y
   contraseñas: nunca se leen—, `esPaquete` —`.numbers`, `.app`…: un documento—, `extracto`, `propiedades`,
   `fechaEnNombre`, `nombreLimpio` —sin el id de Notion—). `HerramientaOrigen`: `ordenada`, `notion`, `drive`,
   `obsidian`, `correo`, `carpetas`. `TipoDocumento` (nota, PDF, imagen, hoja…).
2. `ZonaPreparacion(inventario:layout:hoy:clasificador:huellasDeLaCarpeta:)`: propone con `HeuristicClassifier` (ruta,
   nombre, extensión, texto ya en el Mac y propiedades → `PropuestaDestino` con `coleccion` de `ColeccionV2.catalogo`,
   `destino`, `tipoFicha`, `confianza`, `motivo` en castellano, `origen` reglas/ia/persona, `enSuSitio`).
   `bloques` (`Bloque`: nombre, herramienta, recuento, destino principal), `herramientas`, `duplicados`
   (`GrupoDuplicados`: `identicos` por SHA-256 con el que se queda; `nombreParecido` sin apartar nada hasta elegir).
   Cambios: `cambiarDestino(_:a:)`, `cambiarColeccion(bloque:a:)`, `marcarPrivado(_:)` / `(bloque:)` (deja de verse, del
   mapa y de la IA), `dejarFuera(_:_:)` / `(bloque:_:)`, `fijarAlcance(_ herramienta, .todo | .loActivo(desde:) | .nada)`,
   `quedarseCon(_:enGrupo:)`, `incorporar(_ propuestasIA)`, `aplicar(mapa:)`. `decisiones()` y `mapa()`.
3. IA opcional: `AIClassifier(ejecutor:consentimiento:tamanoLote:)` `.clasificar(zona) async -> ResultadoIA` y luego
   `zona.incorporar(r.propuestas)`. Solo lo de confianza < 0,6, nunca lo privado ni lo sensible, por lotes, con
   `AIClassifier.esquema` (la IA elige una colección del catálogo; la ruta la calcula la app). Sin consentimiento o sin
   ejecutor no hace nada. **`EjecutorClasificacion` (protocolo) lo pone TLSOnboarding** (ver «Cambios pedidos»).
4. `ImportApplier(carpeta:opciones: .init(autor:hoy:ocr:…))`: `preparar(zona) async throws -> VistaPreviaImportacion`
   (`resumen` «Mover 312 · Propiedades a 140 · Archivar 28 · No se borra nada», `movimientos: [MovimientoPrevisto]`,
   `carpetasVacias`, `enlaces`, `enlacesEnRiesgo`, `fechas`, `sinFecha`, `noSeTraen`, `informe`, `mapa`, `plan`,
   `hayCambios`). `aplicar(vista, con: bus, motor: MotorDeDominio?, aceptarEnlacesEnRiesgo:) async throws ->
   ResultadoImportacion` (`planes`, `escritura`, `verificacion`, `informe`, `mapa`, `hashArbolAntes`, `eventosOmitidos`).
   Antes de escribir comprueba que nada cambió desde la vista previa (SHA-256); con `motor`, reglas en modo importación.
   El plan: movimientos con `LinkRefactor` (carpetas enteras de una vez cuando se puede; las que quedan vacías, a
   `Archivo/Importación <fecha>/`), propiedades (`tls_type`, `tls_schema`, `id`; `clase` en proyectos; `fecha_corte` en
   tareas, oportunidades y proyectos traídos de fuera), lo de fuera copiado con sus enlaces arreglados (`LinkRewriter`),
   `Fechas de documentos.csv` (solo filas nuevas; las `manual` no se tocan) y `Buzón/Informe de importación
   AAAA-MM-DD.md`. Choque de nombres: `-2`, `-3` (nunca «(2)»). Tras aplicar: comprobación de todo el árbol (también
   `Archivo/`) y anotación en el informe (segundo plan pequeño).
5. `ResultadoVerificacion.texto` «312 de 312 (recuento + SHA-256)», `sinDiferencias`, `diferencias`.
6. Deshacer: `ImportApplier.deshacer(_ resultado | planes:, con: bus)` y `sePuedeDeshacer` (los dos planes, solo si son lo
   último escrito; si no, `ImportError.deshacerNoDisponible`). Deja el árbol con `hashArbolAntes` (sin `Archivo/`).
7. Calidad: `InformeCalidad.revisar(snapshot:huellas:ignorados:)` (`sinFecha`, `sinTipo`, `duplicado`, `enlaceRoto`;
   `resumen`), `crearTarea(_:snapshot:reloj:autor:) -> WritePlan` y `ignorar(_:estado:)` / `ignorados(estado:)` (en el
   estado de la app, nunca en la carpeta).
8. `MapaImportacion` (`origen,destino,accion,motivo,conflicto`, como `mapa-migracion.csv`): `csv`, `init(csv:)`,
   `guardar(en: estado, nombre:)`, `guardados(en:)`. Guardar el de cada importación en el estado de la carpeta.
9. «Actualizar la copia desde la real» (F3-9): `ActualizacionDesdeLaReal.preparar(real:copia:exclusiones:mapas:)`
   (`nuevos`, `distintos` —no se tocan—, `yaEstan`, `soloEnICloud`, `resumen`, `plan`) y `.aplicar(con: bus)`
   (`Resultado.realIntacta`: el inventario de la real es el mismo).
10. Fechas y OCR sueltos: `DocumentDater(opciones:)` (`fecha(de:ruta:)`, `fechaEnNombre`, `necesitaFila`),
    `OCRService` (`ReconocedorDeTexto`), `FechasDeDocumentos` (`ruta` relativa a Finanzas, como Ribera).

Ampliación sin romper: `TreeWalker.walk(root:cancel:podar:opaca:visit:)` (interno); lo de F0 sigue igual.

## Pantallas de ordenar e importación (rol ordenar: `Sources/TLSOnboarding/Ordenar/**`, `Sources/TLSUI/Importar/**`)

PLAN §6.7 paso 2 y §9 F3 (criterios 1, 2, 4 y 9) sobre el importador del núcleo. Nada se escribe antes de «Aplicar» (dentro
de la pantalla); todo va por `CommandBus`, como la persona, y se deshace. Probado en `Tests/TLSUITests/Importar/` y
`Tests/TLSOnboardingTests/Ordenar/` (21 pruebas, más 4 de capturas) con las capturas en
`build/capturas/f3-ordenar/` (claro y oscuro, solo con `TLS_CAPTURAS`).

- **Escribir** — `AccesoEmpresa` (TLSUI, `@MainActor`): `init?(sesion:)` (la empresa abierta: mismo escritor, avisos y
  ventanas al día) o `init(entry:raiz:appSupport:estado:persona:)` (escritor propio que se abre y se cierra en cada cambio,
  como «Empiezo de cero»). `motivoSoloLectura` (real, solo lectura), `foto()`, `conBus { bus, motor in … }`,
  `escribir(plan:dominio:importacion:aviso:deshacer:)` (con `importacion`, reglas apagadas), `deshacer(planes:)`,
  `sePuedeDeshacer(planes:)`. Errores: `ErrorAccesoEmpresa`. (Se llama así porque TLSOnboarding ya tiene `AccesoCarpeta`.)
- **Modelo** — `ModeloOrdenar(acceso:ruta:hoy:)` (TLSUI, `@Observable`): `RutaOrdenar` `.completar` (copia de G3: «Completar
  las fichas», «Movimientos del banco», «Calidad») u `.ordenar` («Lo que hay», «Preparar», «Por programa», «Repetidos» solo si
  los hay, «Vista previa», «Comprobación», «Calidad»); `PantallaOrdenar` (título = el de `ResumenOrdenar.titulos`, y su
  explicación de 2–3 líneas). `arrancar()` (borrador + inventario), `mirar()`, `parar()`, `anadirFuera(url)` /
  `quitarFuera(alias)` (carpetas de fuera: se copian, el original no cambia), `bloques: [ResumenBloque]` (destino principal,
  motivo, confianza, dudosos, `enSuSitio`), `ficheros(de:)`, `cambiarColeccion(bloque:|fichero:a:)`, `marcarPrivado(bloque:|
  fichero:)`, `volverAVerPrivados()`, `dejarFuera(bloque:|fichero:_:)`, `fijarAlcance(_:_:)` (`corteSugerido`: 1 de enero
  del año pasado), `quedarseCon(_:enGrupo:)`, `ayudaConLosDudosos(consentimiento:)` (solo con `ejecutorIA` y el sí de la
  persona), `prepararVista()`, `motivoNoAplicar`, `aplicar()` (un plan; comprobación por recuento y SHA-256; el mapa va a
  `<estado>/importaciones/`), `cancelarAplicar()` (antes de escribir no se escribe nada; si ya se escribió, se deshace),
  `deshacer()` (todo lo del paso de una vez: importación, anotación, movimientos heredados y tareas de calidad),
  `prepararHeredados()` / `cargarHeredados()` (`LegacyMovementsImporter`, en preparación y con las reglas apagadas),
  `revisarCalidad()`, `crearTarea(_:)`, `ignorar(_:)`, `soloMirar` (repasar: no se escribe nada), `resumenPuesta() ->
  ResumenOrdenar`, `firmaPuesta`. Lo decidido se guarda en `<estado>/ordenar/borrador.json` (fuera de la carpeta; lo
  privado, solo por su huella SHA-256) y se rehace sobre un inventario nuevo al retomar.
- **Vistas** (TLSUI, públicas, Mosaico v2): `OrdenarLoQueHay`, `OrdenarPreparar`, `OrdenarPorPrograma(modelo:multica:)`,
  `OrdenarRepetidos`, `OrdenarVistaPrevia`, `OrdenarComprobacion(modelo:pasadoElPaso3:)`, `OrdenarCalidad`,
  `OrdenarCompletarFichas`, `OrdenarBanco(modelo:abrirBanco:)` y `PantallaOrdenarVista(pantalla:modelo:…)`. Dentro de la
  puesta en marcha, `.environment(\.ordenarSinTitulo, true)` (el título ya va en la cabecera).
- **Puesta en marcha** — `PasoOrdenar(modelo:)` (contrato) pinta la pantalla que toca (por el título de `ordenar.N`);
  cabecera y pie son de `OnboardingFlujo`. `ConexionOrdenar` (TLSOnboarding): `modelo(para:app:)` (uno por carpeta mientras
  dura la ventana; por la sesión abierta si la hay), `sincronizar(_:_:)` (pantallas y planes a `registrarOrdenar`; «Nada
  que ordenar» si la vista previa no tiene cambios; si se deshace, `marcarDeshecho`), `buscarClaude` (sustituible en pruebas;
  el de verdad solo con `usarAsistente` y por el `detectorClaude` del entorno), `registrar(_:para:)`, `olvidar(_:)`. Tras
  «Aplicar» en la vista previa se pasa sola a «Comprobación» (`avanzar()`).
- **Actualizar la copia desde la real** — `ActualizarCopiaHoja(sesion:registro:)` / `(acceso:real:)` y
  `FilaActualizarCopia(sesion:)` (para Ajustes › Esta empresa): la real (la registrada como real con esa ruta, o
  `entry.origen`) solo se lee; vista previa «Traer 3 nuevos · 1 distinto no se toca · No se borra nada»; «Añadir N
  ficheros» en un plan (⌘Z de la ventana o «Deshacer» de la hoja); después, «N de N comprobados por su SHA-256» y «Tu
  carpeta real no ha cambiado».
- **Multica** — `ImportarMulticaHoja(acceso:)` (desde la puesta en marcha, con «Deshacer» en la hoja), la pastilla «N
  nuevas» y, la segunda vez, «0 nuevas: ya las importaste todas» con «Cerrar». `init(sesion:)` sigue igual.

## Pantallas de la puesta en marcha (rol pasos: `Sources/TLSOnboarding/**` salvo `Ordenar*`)

PLAN §6.7 (patrón de cada paso y normas) y §9 F3 (criterios 1, 2, 3, 5, 6 y 10) con Mosaico v2: ventana limpia sin barra
lateral; cabecera azul noche con «Puesta en marcha · paso N de M · <paso>», el título, la explicación de 2–3 líneas,
«Quedan ~N min» y «Seguir más tarde» (siempre visibles); barra de avance por pasos; la pantalla; y el pie con «Atrás»
(⌘[), «Saber más» (`BotonSaberMas(seccion: "paso-<raw>")`), «Saltar este paso» y el botón principal (↩). Un destacado
violeta como mucho (solo el cuello de «Lo que he entendido»). Probado en `Tests/TLSOnboardingTests/` (`RutasPasosTests`,
`BienvenidaPasosTests`, `ComportamientoPasosTests`, `GlosarioPasosTests`; capturas con `TLS_CAPTURAS` en
`build/capturas/f3-pasos/`, claro y oscuro).

- **Escena y ventana** — `OnboardingEscena()` y `OnboardingEscena(entorno:)`; `OnboardingVentana(peticion:)` y
  `(peticion:entorno:)` (el modelo se crea una vez, al aparecer; si el entorno no trae `app`, toma `@Environment(AppModel.self)`
  si lo hay); `OnboardingFlujo(modelo:)`. La escena deja puesto `ControladorTutorial.repasarPuestaEnMarcha` (abre la ventana
  en `.repasar`) desde sus menús, que se construyen al arrancar.
- **Entorno** — `EntornoPuesta` (`@MainActor`, `compartido`): `app: AppModel?` (con él, «Aplicar» escribe por la sesión
  abierta), `instalarEjemplo` (sin él, «Ver un ejemplo» abre el selector, que lo tiene), `comprobarAcceso` (`AccesoCarpeta`:
  `ok`, `sinPermiso`, `noExiste`, `otro`; abre la carpeta sin listarla ni descargar nada), `paneles: PanelesPuesta`
  (`PanelesDelSistema`: carpeta, «dentro de» para lo privado y fichero para el logo), `detectorClaude: DetectorClaude`
  (`DetectorClaudeCode`: `ClaudeLocator` para buscarlo; «Probar» y el lanzador del entrevistador con `LanzadorClaudeCode`),
  `almacenTutorial`, `abrirAjustes`, `mostrarEnFinder`; `tutorialEn(_:)` y `recorridoEnCurso(empresa:)` para pruebas.
  `AccionesVentana(abrirEmpresa:abrirSelector:cerrar:)` la pone la ventana (`openWindow.abrirEmpresa`, el selector y `dismiss`).
- **`ModeloPuesta` ampliado (sin cambiar sus firmas)** — estado: `peticion`, `registro`, `appSupport`, `empresas`,
  `entorno`, `ventana`, `borradores` (texto a medio escribir; se guarda al pulsar ↩, al salir del campo o con cualquier
  botón), `copia: EstadoCopia?`, `incluirArchivo`, `privadasPorConfirmar`, `claude: EstadoClaude`, `aplicado:
  ResumenAplicado?`, `pintadas` (pantallas pintadas, para contar), `empresaAlTerminar`, `terminada`, `ocupado`. Lo que se ve:
  `accionPrincipal: AccionPrincipal` (`siguiente`, `aplicar`, `hacerCopia`, `abrirSinTocar`, `crearCarpeta`, `abrirEjemplo`,
  `abrirAjustes`, `empezarRecorrido`, `terminar`, `abrirMiCarpeta`), `motivoSinPrincipal` (el porqué al lado del botón),
  `respuesta(_:)`, `pasoHecho(_:)`, `esUltima`, `yaHayCarpeta`, `repasando`, `carpetaDeOrigen`, `privadasElegidas`,
  `faltaParaLaCarpeta`. Botones: `pulsarPrincipal()`, `avanzar()`, `atras()`, `saltarPaso()` (`omitir`),
  `seguirMasTardeYCerrar()`, `contestar(_:_:)`, `noLoSeYGuardar(_:)`, `guardarBorradores(solo:)` (`false` si el
  entrevistador repregunta: se enseña y no se sigue), `aplicarPasoActual()`, `deshacerPaso(_:)`, `elegirCarpetaDeOrigen()`,
  `elegirPrivadas()`, `noHayPrivadas()`, `quitarPrivada(_:)`, `hacerCopia()` (`DemoCopier` + registro + `registrarCopia`),
  `cancelarCopia()`, `abrirSinTocar()` (`AppModel.registerReadOnly` y abrir), `crearEmpresa()` (`aplicarEmpezarDeCero`),
  `abrirEjemplo()`, `reintentarPermiso()`, `detectarClaude()`, `probarClaude()`, `usarAsistenteYConectar(_:)`, `terminar()`
  (si se pidió, `TutorialEventos.empezar(.tuEmpresa, …)`; abre la empresa y cierra), `alPintar(_:)`,
  `programarVistaPrevia()` / `prepararVistaPreviaSiToca()`.
- **Aplicar** — la vista previa se rehace sola al contestar (y nunca mientras un botón trabaja: lo que se escribe es lo
  que se enseñó). «Aplicar» guarda lo escrito, comprueba lo que falta, rehace la vista previa y la escribe con
  `ModeloPuesta.aplicar(bus:)`: por la sesión abierta de la empresa si `entorno.app` la tiene, o con un `VaultWriter` propio
  (estado en `<appSupport>/<id>`) que se cierra al acabar. Después vuelve a leer la carpeta (`cambiarContexto`) para que lo
  siguiente llegue premarcado con lo recién escrito. El resumen («Hecho: Crear 9 · Cambiar 2 · No se borra nada») sale
  arriba con «Deshacer».
- **Vista previa legible** — `DiferenciaLegible`: «Nueva: Diagnóstico», «Esto se añadirá a «X»» o «Cambia «X»», por áreas;
  al abrir una fila, las líneas nuevas (+), las que dejan de estar (tachadas) y las propiedades por su nombre; los ajustes de
  la carpeta, en palabras («Qué funciona sin ti: quién hace cada función»). Nada de rutas técnicas en pantalla.
- **Pasos** — `PasoBienvenida` (tres opciones grandes; tu carpeta con la explicación del permiso de iCloud antes de
  «Elegir carpeta…», copia o ver sin tocar, lo privado obligatorio con selector y chips, «Incluir Archivo», el avance de
  la copia con «Cancelar»; recuperación con los tres pasos y «Volver a intentarlo»; tu empresa y lo que se crea),
  `PasoAlcance` (proceso / área / todo, el área o el proceso, y el consentimiento para Claude Code), `PasoConocer`
  (encuadre, la frase con sus cinco huecos y cómo queda, adónde quieres llegar, una pantalla por área con escalas 1–5
  grandes, dolor y meta, la cadena de etapa que se para en el primer «no» y la cita; «Lo que he entendido» con el cuello
  en el destacado y la foto de las áreas; el resumen de G3), `PasoOrganizar` (estados, vocabulario plegado, rol y quién lo
  lleva, sistemas, ofertas y embudo, plan de entrega, logo; resumen de G3), `PasoSinTi` (por sistema, con sus funciones y
  lo sensible bloqueado en «Siempre con tu OK»), `PasoDiaADia`, `PasoNumeros` (número, meta y alerta con «Sin meta»; el
  objetivo opcional), `PasoConectar` (Claude Code buscado al llegar y «Probar»; Banco por extracto; Mail, Calendario, Otros
  programas y Avisos «Llega en la próxima versión»; «Trabajar con la ventana cerrada», apagado) y `PasoRecorrido` (las
  cinco marcas y «Cómo ha quedado»). (`HuecoPaso` se quitó en la integración: ya no lo usaba nadie.)
- **Accesibilidad** — además de los del andamio: `puesta.atras`, `puesta.saltar`, `puesta.quedan`, `puesta.avance`,
  `puesta.error`, `puesta.resumen`, `puesta.deshacer`, `puesta.noLoSe.<id>`, `puesta.opcion.<id>.<opción>`,
  `puesta.escala.<id>.<n>`, `puesta.si.<id>` / `puesta.no.<id>`, `puesta.elegirCarpeta`, `puesta.privadas.si|no`,
  `puesta.copia`, `puesta.cuello`, `puesta.probarClaude`, `permiso.explicacion`, `permiso.recuperacion`.

## Integración (rol integración: App, `TLSUI/Shell`, `project.yml`, versión 0.4.0)

Todo lo de arriba, unido en la app. TLSUI sigue sin depender de TLSOnboarding: abre la puesta en marcha por su
identificador (`PuertaPuestaEnMarcha.ventanaID`) con una `PeticionPuestaEnMarcha`. Probado en
`Tests/TLSOnboardingTests/IntegracionPuestaTests.swift` (F3-6 y las entradas) y en las pruebas de cada rol.

- **App** (`App/Sources/TheLastSystemApp.swift`): un solo `AppModel.deLaApp()` para `TLSScenes(model:)` y
  `OnboardingEscena(entorno: EntornoPuesta.deLaApp(model))`. `project.yml` enlaza el producto `TLSOnboarding`.
- **`TLSScenes(model:)`** (y `init()`, que crea el suyo): selector, ventanas de empresa, `EscenaManual()` (ventana
  «Manual») y Ajustes; los menús `ComandosEmpresa` y `ComandosAyuda(model:)` (Ayuda › «Manual de The Last System» ⌘?,
  «De dónde salen las ideas», «Conoce la app con un ejemplo», «Recorrido con tu empresa»). En Archivo: «Empezar / Seguir
  con / Repasar la puesta en marcha…» (`PuestaDeLaEmpresa.tituloMenu`), «Actualizar la copia desde la real…»
  (`HojaVentana.actualizarCopia`, solo en copias que saben de qué carpeta real salieron) e «Importar tareas de Multica…»
  (`HojaVentana.importarMultica`).
- **`AppModel`**: `deLaApp()` (preferencias del Mac, `prepararEscritura()` y `abrirPuestaAlArrancar`), `appSupport` (el
  del registro) e `instalarEjemplo(origen:empresas:)` (el `InstaladorEjemplo` de siempre, para la puesta en marcha).
- **Arranque** (`Launcher/LauncherView`): la primera vez (sin empresas ni puestas en marcha a medias) se abre la puesta en
  marcha en lugar del selector; si no, arriba una fila «Seguir con la puesta en marcha · paso N de M» por cada una a medias
  (`PuestaDeLaEmpresa.pendientes`, con el nombre de la carpeta o el contestado; como mucho tres; no salen las de una
  carpeta que se quitó de la lista) con «Seguir». En la
  cabecera, «Empezar de cero…» (`PeticionPuestaEnMarcha(modo: .empezar, como: "cero")`, llega elegido). Al terminar
  «Crear copia de mi carpeta…», «Ponerla en marcha» (principal) o «Abrir la copia».
- **Hoy** (`AvisoPuestaEnMarcha(sesion:progreso:)`): mientras no esté terminada, bajo la cabecera, «Seguir con la puesta
  en marcha · paso N de 9», «Quedan ~N min · lo que ya contestaste está guardado» y «Seguir» (`.retomar`). `HoyPantalla`
  lo lee al abrir, tras cada cambio y al volver a la ventana (una vista vacía no recibe `.task`). Ribera (hecha) no la
  enseña.
- **Ajustes › Esta empresa** (`FilasPuestaEnAjustes`): «Puesta en marcha» (Sin empezar / Paso N de M / Terminada, con
  Empezar, Seguir o Repasar), `FilaActualizarCopia(sesion:)` e «Importar tareas de Multica…».
- **Ventana de la puesta en marcha**: con el `AppModel` en el entorno (y su tamaño de texto). «Seguir más tarde» sin otra
  ventana abierta vuelve a abrir el selector (para que la app no se quede sin ventana).
- **⇧⌘R «Mostrar en Finder»** cuenta para el hito del tutorial (`VaultSession.revealInFinder` manda `.vistaEnFinder`).
- **Duplicados quitados**: `FolderAccess` (`check`, `revealInFinder`, `openPrivacySettings`, `mensajeOtro`) y
  `FolderPanels` (`chooseCompanyFolder`, `choosePrivate`) son públicos; `AccesoCarpeta.comprobar` y `PanelesDelSistema`
  los usan. `HuecoPaso` (cuerpo provisional, ya sin uso) se ha quitado.
- **Motor (ampliado, sin cambiar firmas)**: `olvidar(_ id:)`; la etapa contestada manda sobre la calculada (`etapaDeArea`
  mira primero lo que dice la persona); «¿Cómo funcionan hoy las ventas / las finanzas?» (`TextosPuesta.funciona`);
  `.modo` llega premarcado «Trabajar sobre una copia (recomendado)»; `ResumenOrdenar.explicaciones` (y
  `ResumenOrdenar.explicacion(_ titulo:)`, la misma tabla que `PantallaOrdenar.explicacion`) para que la cabecera diga lo
  de cada pantalla del paso 2 (dentro de la puesta en marcha `CabeceraOrdenar` ya no la repite);
  `EstadoPuestaEnMarcha.sinEmpezar` (las abiertas y cerradas en la bienvenida sin contestar nada no salen en el
  arranque);
  `ProgresoPuestaEnMarcha.de(_:)`; sobre una copia ya hecha la ruta se fija al abrir (`fijarRutaDeLaCopia`: no cambia
  de ruta tras ordenar y Hoy cuenta «paso N de 9» igual que la ventana); `PeticionPuestaEnMarcha.como` (opcional).
- **Núcleo**: `VaultWriter` ya no guarda copia previa de lo que solo se mueve o se renombra (se deshace moviéndolo de
  vuelta, comprobado por su huella): una importación con muchos PDF no dobla el espacio. `LinkRefactor.validate` lleva la
  vista al día con cada traslado en vez de rehacerla (deja de ser cuadrático).
- **Banco (F2)**: los registros de facturas de antes (G3: `id,fecha,cliente,concepto,importe`) se leen con sus columnas
  (`RegistrosFinanzas.columnasDeAntes`) y, al «Cargar en preparación» movimientos heredados en ellos, cada dato va a su
  columna equivalente; si el registro no guarda el número de factura, no cuenta en la clave. La segunda vez dice «0
  nuevos · N ya cargados» (antes los ofrecía otra vez). Lo que el registro de antes no puede guardar (p. ej.
  `estado_revision`) se dice antes de cargar (`columnasQueNoCaben`). Decisión: el `importe` de G3 se lee como el total
  de la factura (si en la carpeta de Manu fuera la base sin IVA, habría que leerlo como `base` en `columnasDeAntes`).
- **Lint del glosario (F3-10)**: `GlosarioTests.literalesDeLasVistas` revisa también `TLSOnboarding`.
- **Rutas en pantalla**: `TLSFormat.rutaCorta` dice «iCloud Drive/…» en vez de la carpeta técnica de iCloud (la carpeta
  de origen de la bienvenida y el selector).
- **Capturas**: `make capturas` pinta también F3 en claro y oscuro (`build/capturas/f3-pasos`, `f3-ordenar`,
  `f3-tutorial`, `f3-integracion` y el índice `build/capturas/f3.html`). Las del tutorial sobre la ventana entera dejan la
  columna de la barra lateral en blanco: `NavigationSplitView` no la pinta fuera de pantalla (en la app sí sale).
- **DMG**: `LEEME.txt` dice qué pasa la primera vez (la puesta en marcha) y dónde está el manual.

### Criterios de aceptación (PLAN §9 F3) y su prueba

| # | Criterio | Pruebas |
|---|---|---|
| F3-1 | 0 escrituras antes de «Aplicar» | `AplicarPuestaTests` «Ribera y G3: ninguna escritura…» (vigilante FSEvents + huella), «Empresa nueva: no existe nada en el disco hasta Aplicar»; `ComportamientoPasosTests` F3-1 (la copia de G3 entera por las pantallas); `ImportApplierTests` y `OrdenarModeloTests` F3-1 (paso 2); `RevisionFinalF3PantallasTests` «Completar las fichas: el pie es «Aplicar»» (ya no se pasa sin aplicar) |
| F3-2 | Copia de G3 ≤ 15 pantallas; empresa nueva ≤ 40 | `RutasPuestaTests` (motor; G3 con «Quedan ~N min» por pregunta, 15–30) y `RutasPasosTests` (pintando cada pantalla y pulsando el botón principal); `PasoOrdenarTests` (3 pantallas de ordenar en G3); `RevisionFinalF3MotorTests` (minutos por pregunta, Hoy = ventana) |
| F3-3 | «Seguir más tarde», cerrar y abrir: misma pregunta y respuestas | `RetomarYEntrevistaTests`, `ComportamientoPasosTests` F3-3, `OrdenarModeloTests` «Seguir más tarde», `IntegracionPuestaTests` (arranque); `RevisionF3DatosPuestaTests` (una respuesta ilegible o de otra versión no se lleva las demás; un `onboarding.json` ilegible se aparta, no se pisa) |
| F3-4 | Importar: 0 borrados, recuento + SHA-256 sin diferencias; «Deshacer» deja el hash previo | `ImportApplierTests` F3-4 (dos), `OrdenarModeloTests` «Lo aplicado es lo que enseñaba…», `OrdenarIntegracionTests`; `RevisionF3DatosOrdenarTests` (sobre una copia hecha con `DemoCopier`, con lo privado y `Archivo` fuera; lo marcado privado queda en `privado:` y «Deshacer» lo quita) y `RevisionF3DatosImportarTests` |
| F3-5 | «No lo sé» → PENDIENTE | `AplicarPuestaTests` «No lo sé se escribe PENDIENTE…», `RutasPasosTests` (empresa nueva), `ComportamientoPasosTests` F3-5; `RevisionF3DatosPuestaTests` («¿Funciona sin ti?» → `ejecutor: PENDIENTE`; número clave → `numero_clave: PENDIENTE`); `RevisionFinalF3PantallasTests` («Lo contesto luego») |
| F3-6 | «Ver un ejemplo» llega a Hoy en ≤ 2 min | `IntegracionPuestaTests` F3-6 (instalador de verdad, ventana de la empresa y Hoy con datos; ~1 s) |
| F3-7 | «Reiniciar ejemplo» devuelve los hashes prístinos | `TutorialTests` «Reiniciar ejemplo devuelve los hashes prístinos…» |
| F3-8 | El tutorial de Ribera, completo | `TutorialTests` «Recorre el tutorial de Ribera completo…» (los 8 hitos con su acción real y los 2 que llegan con los asistentes) y «F3-8 · las anclas» (las 9 anclas, cada una en su pantalla) |
| F3-9 | «Actualizar la copia» deja intacto el inventario de G3 | `OrdenarIntegracionTests` F3-9 (la fixture G3 como carpeta real), `CalidadYActualizarTests` F3-9 |
| F3-10 | Lint del glosario | `GlosarioTests` (con TLSOnboarding), `GlosarioPasosTests`, `RetomarYEntrevistaTests.glosario`, `GlosarioImportarTests`, `ManualTests` |

## Revisión final (corrector final de F3)

Aplicados los hallazgos confirmados de las dos revisiones (datos y privacidad; experiencia y diseño). Las pruebas que
los reproducían (`Tests/*/RevisionF3DatosTests.swift`) ya no llevan `withKnownIssue`: comprueban que no vuelven. Las del
corrector están en `Tests/TLSCoreTests/RevisionFinalF3Tests.swift` y `Tests/TLSOnboardingTests/RevisionFinalF3Tests.swift`.
Resultado: 1065 pruebas en 184 suites, 0 fallos conocidos, 0 avisos (también compilando desde limpio).

### Datos y privacidad (los 14, más 3 de los «pendientes sin prueba»)

| # | Arreglo | Dónde |
|---|---|---|
| 1 | Sobre una copia, lo dejado fuera al copiar (rutas de la real: la carpeta privada y `Archivo`) ya no se exige: solo se excluye lo que existe y `Archivo/` nunca (es el Archivo de verdad de la copia). Ordenar, la vista previa y «Calidad» arrancan en copias hechas por la app. | `FuenteImportacion.exclusionesDeLaCopia`, `InventarioImportacion.inventariar`, `ImportApplier.preparar`, `ModeloOrdenar` |
| 2 | «Es privado…» queda privado: «Aplicar» lo declara en `privado:` de `.tls/config.yaml` en el mismo plan (se deshace con él) y la vista previa lo dice. | `ZonaPreparacion.privadasDeLaEmpresa`, `VaultLayout.configConPrivado`, `VistaPreviaImportacion.privadas` |
| 3 | Lo privado no cuenta para los repetidos: se recalculan solo con lo visible (y se conserva «el que se queda» elegido). La ruta privada no sale en el mapa ni en el informe. | `ZonaPreparacion.recalcularDuplicados` |
| 4 | El plan no edita notas privadas: la foto de `LinkRefactor` no las ve y ocupan su sitio en los nombres libres. La vista previa avisa, sin nombrarlas, de que sus enlaces no se tocan. | `ImportApplier.preparar`, `NombresLibres.reservarFichero` |
| 5 | Un enlace a algo de fuera que no se trae por repetido lleva a donde queda el que se conserva; lo que sigue sin destino dentro de la fuente sale en «Enlaces que dejarían de funcionar». | `LinkRewriter.quedanRotos`, `ImportApplier.traer(redirigidos:)`, `ProblemaDeEnlace.init` (ahora público) |
| 6 | «Actualizar la copia»: un fichero ordenado que cambió en la real sale en «Distintos». El mapa guarda el SHA-256 de cada origen (columna nueva `sha256`, opcional al leer); sin él, se compara con la copia (en notas, el texto sin las propiedades que añadió ordenar). | `FilaMapa.sha256`, `ActualizacionDesdeLaReal.cambioDesdeQueSeOrdeno` |
| 7 | Lo que no se puede traer sale aparte con su motivo («No los puedo traer») y no cuenta como traído. | `ActualizacionDesdeLaReal.noSeTraen`, `ActualizarCopiaHoja` |
| 8 | `onboarding.json` se lee respuesta a respuesta y paso a paso (lo que no se entiende se salta; las claves que falten toman su valor de serie). Un fichero que no se puede leer no se pisa: se aparta como `onboarding.json.ilegible-<fecha>`. | `EstadoPuestaEnMarcha.init(from:)`, `Respuesta.init(from:)`, `Tolerante`, `AlmacenPuesta.ilegible/apartarIlegible`, `ErrorPuesta.estadoIlegible` |
| 9 | Paso 4: un asistente (`ejecutor: IA`) solo con el «Sí» de la persona y siempre con `modo: supervisado`. «Funciona sin ti» sin asistente: `H` (o `A`/`S` si el estándar lo recomienda) con `sin_ti: si`. | `PlanesPuesta.sinTi`, `DeclaracionCapacidad.sinTi` |
| 10 | «No lo sé» en «¿Funciona sin ti?» escribe `ejecutor: PENDIENTE`. | `PlanesPuesta.sinTi` |
| 11 | «No lo sé» en el número clave escribe `numero_clave: PENDIENTE` en el `Área.md` (se lee como «No lo sé» al volver; meta y alerta no se preguntan). | `PlanesPuesta.numeros`, `ContextoCarpeta.numeroClavePendiente` |
| 12 | Multica: salud corriente (clínica, vacuna, sangre, preoperatorio, «-ólogo/-óloga»…) sale desmarcada. | `ClasificadorPersonal` |
| 13 | Multica: «Hecho», «Cancelada», «Won't do» y sus variantes en español e inglés se reconocen; un estado desconocido sale desmarcado y lo dice. | `CategoriaMultica.init(leyendo:)`, `TareaMultica.estadoDesconocido` |
| 14 | Multica: una tarea importada que está en el Archivo (retirada o deshecha) sale desmarcada («Ya la importaste y está en el Archivo»); se puede marcar si se quiere de vuelta (así «Deshacer» la importación sigue permitiendo traerlas). | `ImportadorMultica.enElArchivo`, `CandidataMultica.enArchivo` |
| + | Un paquete (`.numbers`…) con algo solo en iCloud cuenta como «solo en iCloud»: no se trae ni se mueve a medias. | `InventarioImportacion.paquete` |
| + | En modo importación lo pendiente de antes ya no se marca como omitido: se queda pendiente para cuando acabe. | `MotorDeDominio.procesarPendientes` |
| + | `registrarCopia`: si no se puede guardar el estado nuevo, no se quita el de antes. | `OnboardingEngine.registrarCopia` |

### Experiencia y diseño

| # | Arreglo |
|---|---|
| P1-1 | En «Vista previa» y «Completar las fichas», mientras el paso está por aplicar, el botón del pie (↩) es **«Aplicar»** (desactivado con su motivo si aún no hay vista previa) y aplica el `ModeloOrdenar`; dentro de la pantalla ya no hay otro. Sin nada que hacer, «Siguiente». (`AccionPrincipal.aplicarOrdenar`, `ConexionOrdenar.porAplicar/pantalla(para:ordenar:)`, `EnvironmentValues.ordenarAplicarEnElPie`). Sustituye a lo de «ordenar (hecho)»: «el pie sigue diciendo «Siguiente»». |
| P1-2 | Los resúmenes (copia de G3) enseñan lo premarcado; lo que no llegó premarcado va plegado en **«Lo que falta (N)»** con **«Lo contesto luego»** (lo deja en «No lo sé» → PENDIENTE). «Quedan ~N min» se cuenta por pregunta (resumen: 0,5 + 0,05 por premarcada + 0,2 por cada blanca sin contestar; formulario: 0,2 por pregunta, mínimo 1,5) y se guarda en `onboarding.json` (`quedan_minutos`) al cambiar de pantalla, para que Hoy y el arranque digan lo mismo que la ventana. La explicación de cada resumen nombra las fuentes que de verdad se leyeron (o dice que no encontró nada). (`OnboardingEngine.enBlanco/contestarLuego/minutos(de:)/explicacionResumen`, `LoQueFalta`) |
| P1-3 | «Qué funciona sin ti» usa **los mismos sistemas que Organizar** (`SistemaCatalogo`, con los mismos nombres) y no vuelve a preguntar si está montado: lo dice Organizar («Montado · Lo dijiste en Organizar»). Solo pregunta «¿Funciona sin ti?» y «¿Lo dejo a un asistente?» de lo montado; lo que falta no sale. Las funciones de cada uno salen de `SistemaCatalogo.mapaEstandar` (p. ej. Embudo → VEN-2 y VEN-3). Las preguntas `sinti.<sistema>.*` usan ahora el código de Organizar (`FI1`), y `sistemasSinTi` es `[SistemaCatalogo]`. |
| P2-4 | Sin números de paso en los textos («hasta que apliques «Organizar»») ni en los títulos del manual. |
| P2-5 | «Ahora no» desactivado: relleno y texto de botón desactivado de Mosaico §1.3, sin ✓ ni transparencia. |
| P2-6 | Una sola cifra de carpetas privadas, sin contar `Archivo` (`VaultEntry.carpetasPrivadasDeLaCopia`); tampoco se premarca `Archivo` como privada. |
| P2-7 | «Revísala y pulsa «Crear la carpeta»». |
| P2-8 | En una empresa nueva, el alcance premarcado dice por qué de verdad («tu empresa es nueva…»). |
| P2-9 | «Sin alerta» en la alerta (y en Metas); aviso en la fila si meta y alerta van al revés del sentido del número. |
| P2-10 | Calidad: «Poner fecha…» (calendario → fila `manual` en «Fechas de documentos», se deshace con el paso; `RevisionFinalF3CalidadTests`) y textos que mandan a sitios que existen. |
| P2-11 | Columnas en palabras y con tildes («estado de revisión», «número de documento») en el banco y en ordenar (`NombreDeColumna`). |
| P2-12 | Fuera la jerga en explicaciones y pantallas: «comprobado por su huella digital». Se conserva la cifra «312 de 312 (recuento + SHA-256)» del informe y de `ResultadoVerificacion.texto`, que PLAN §6.7 fija literalmente (en la pantalla sale como ayuda al pasar por encima). |
| P2-13 | Tutorial: un solo contador («N de 8 hitos») y «ocho cosas (y dos más llegan con los asistentes)». |
| P2-14 | El ejemplo, al repasarlo, sale completo (`RespuestasDelEjemplo`, datos inventados coherentes con Ribera, solo en su `onboarding.json`); al repasar no hay «Quedan ~N min» ni «Lo contesto luego» («Solo se mira»). |
| P2-15 | Títulos de varias áreas: «Dirección, Ventas y Entrega» o «Tus seis áreas» (`TextosPuesta.listaDeAreas`). |
| P2-16 | «Cinco cosas para probar»; Mika se presenta («tu asistente de Dirección»). |
| P2-17 | Los campos de cifras llevan ejemplo («Por ejemplo: 3») en vez del título cortado. |
| P3 | Empate en «Lo que he entendido» (se dice por qué se empieza por esa); «cuello» explicado; «Copiar también lo retirado»; «Sin dudas» en vez de «Seguro»; nombres sin `.md`; «Crear N ficheros»; «carpeta real» siempre; el manual ya no promete que «todo» se deshace. |

### Cambios de API y de formato (anotados para F4)

- **TLSCore**: `VaultLayout.configConPrivado(_:anadir:)`; `ProblemaDeEnlace.init` público; `VaultEntry.carpetasPrivadasDeLaCopia`;
  `AlmacenPuesta.ilegible` y `apartarIlegible(ahora:)`; `ErrorPuesta.estadoIlegible`; `EstadoPuestaEnMarcha.quedan`
  (`quedan_minutos`); `OnboardingEngine.enBlanco(_:)`, `contestarLuego(_:)`, `minutos(de:)`, `montadoEnOrganizar(_:)`;
  `sistemasSinTi: [SistemaCatalogo]` (antes `[SistemaStd]`); `SistemaCatalogo.mapaEstandar`, `estandar`, `deEstandar(_:)`;
  `TextosPuesta.listaDeAreas(_:)`; `ConfigMetricas.DeclaracionCapacidad.sinTi` (`sin_ti` en `capacidades:`).
- **TLSImport**: `FuenteImportacion.exclusionesDeLaCopia(_:raiz:archivo:fileSystem:)`; `ZonaPreparacion.privadasDeLaEmpresa`;
  `VistaPreviaImportacion.privadas` (y `hayCambios` cuenta lo privado por declarar); `ImportError.ajustesIlegibles`;
  `FilaMapa.sha256` (columna `sha256` del mapa); `ActualizacionDesdeLaReal.noSeTraen`; `InformeCalidad.ponerFecha(_:fecha:snapshot:autor:)`;
  `ImportadorMultica.enElArchivo()`, `CandidataMultica.enArchivo`, `TareaMultica.estadoDesconocido`.
- **TLSUI**: `ModeloOrdenar.ponerFecha(_:fecha:)`; `EnvironmentValues.ordenarAplicarEnElPie`.
- **TLSOnboarding**: `AccionPrincipal.aplicarOrdenar`; `ConexionOrdenar.pantalla(para:ordenar:)` y `porAplicar(_:)`;
  `ModeloPuesta.contestarLuego(_:)`.
- **Formato que se escribe**: `privado:` de `.tls/config.yaml` puede crecer al ordenar; `capacidades:` puede llevar
  `sin_ti: si` y `ejecutor: PENDIENTE`; `Área.md` puede llevar `numero_clave: PENDIENTE`; Metas puede decir «Sin alerta».
  Falta anotarlos en el diccionario de la propuesta (lo decide Manu).

### Lo que queda (con su motivo)

- **↩ dentro de un campo de texto**: en macOS, ↩ en un campo puede pulsar el botón principal («Aplicar»). No se puede
  comprobar fuera de pantalla; está en la guía de prueba manual.
- **P3-21 y P3-22** (casillas y segmentados del sistema; cabecera compacta con texto al 130 %): hay que verlos con la
  ventana activa y VoiceOver; no se tocan sin poder comprobarlos.
- **P3-23** (Esc en el tutorial): es una decisión del rol tutorial (↩ y Esc son de quien escribe en el editor); se
  mantiene.
- **Multica en una copia hecha por la app**: las tareas personales necesitan una carpeta privada dentro de la copia, y la
  copia no la tiene (lo privado se quedó fuera). Hace falta «Crear una carpeta privada» en la hoja (F4).
- **«Que se vean los nombres que elige la persona»** y el diccionario de la propuesta: siguen pendientes (ver
  «Integración»).

## Cambios pedidos

### motor

- **integración (App y XcodeGen):** declarar la escena `OnboardingEscena()` en la app y enlazar el producto
  `TLSOnboarding` en `project.yml` (el paquete ya lo exporta). Nada más: la ventana se abre por su `id`.
- **integración (Launcher, `TLSUI/Launcher/LauncherView.swift`):** «Empezar de cero» → `openWindow(id:
  PuertaPuestaEnMarcha.ventanaID, value: PeticionPuestaEnMarcha(modo: .empezar))`; si
  `AlmacenPuesta.pendientes()` no está vacía, una fila «Seguir con la puesta en marcha» por cada una (`.retomar` con su
  `vaultID`); al crear una copia, ofrecer la puesta en marcha (`.empezar` con el id de la copia: llega premarcada).
- **integración (Hoy, rol hoy-decisiones de F2, `HoyPantalla`):** si `PuertaPuestaEnMarcha.avisoDeHoy(vaultID:
  sesion.entry.id)` no es `nil`, la línea «Seguir con la puesta en marcha · paso N de M» con «Quedan ~N min» y el botón
  que abre la ventana (`.retomar`). F2 dejó escrito «"Seguir con la puesta en marcha" no sale hasta F3».
- **integración (lint del glosario, criterio F3-10):** añadir `"TLSOnboarding"` a la lista de módulos de
  `Tests/TLSUITests/Integracion/GlosarioTests.literalesDeLasVistas`. Los textos del motor ya los revisa
  `RetomarYEntrevistaTests.glosario` (todas las pantallas, preguntas, opciones, orígenes y resúmenes de las rutas).
- **integración (lectura de `vocabulario:`):** el paso 3 escribe `vocabulario: {cliente, oportunidad, proyecto,
  servicio}` en `.tls/config.yaml`; aún no hay quien lo lea para enseñar esos nombres en pantalla.
- **pasos:** «Aplicar» por `sesion` cuando la empresa esté abierta (`CommandBus` del escritor de la sesión) y, si no lo
  está, abrir un `VaultWriter` como en `AplicadorPuesta.empezarDeCero` y cerrarlo al terminar. Tras aplicar,
  `cambiarContexto(.leer(…))` para que lo siguiente salga premarcado con lo recién escrito. Con carpeta, en la bienvenida:
  `DemoCopier` (TLSImport) → `registrarCopia`; si macOS deniega el permiso, `permisoDenegado(true)`. El logo «Ya lo tengo»
  responde `.rutas([ruta absoluta])` a `PreguntaID.logoFichero`. Detectar Claude Code (paso 7) con `ClaudeLocator` y, con
  el consentimiento, poner `motor.entrevista.lanzador = LanzadorClaudeCode(…)` (`actualizar { $0.entrevista = … }`).
- **ordenar:** al terminar, `registrarOrdenar(ResumenOrdenar(pantallas:titulos:movidos:completadas:archivados:
  verificados:planes:texto:), aplicado: true)`; el tope de 15 pantallas de la copia de G3 cuenta con **3** pantallas de
  ordenar (completar las fichas, movimientos y calidad).
- **tutorial (hecho por su lado, comprobado):** usa `ejemploCompletado` y los `id` de `HitoRecorrido`.
- **diccionario (SISTEMAS §1.5):** propiedades nuevas que escribe la puesta en marcha: `areas_activas` (Empresa.md, ya en
  la plantilla), `## Encuadre` en Diagnóstico (no está en la plantilla «Diagnóstico»), `declarada: a medias` y
  `declarada: PENDIENTE` en `capacidades:` (la lectura de métricas las cuenta como no declaradas).
- **Decisiones del motor (por si Manu prefiere otra cosa):** una empresa nueva se registra `clase: copia` (no hay
  original); el paso 4 usa los 24 sistemas del estándar (`sistemas-std.json`, con sus funciones) y el paso 3 los 19 de la
  propuesta v2 (fichas); «a medias» no declara la función; la alerta propuesta es ±20 % de lo de los últimos 90 días;
  la «tarjeta de revisión a los 7 días» es una tarea planificada (Hoy la enseña ese día).

### tutorial

- **integración (Shell):** en `TLSScenes`, añadir `EscenaManual()` y `.commands { ComandosAyuda(model: model) }` (la ventana
  del manual y el menú Ayuda). En `VaultSession.revealInFinder` (o en el menú «Mostrar en Finder»), llamar a
  `TutorialEventos.registrar(.vistaEnFinder(ruta), empresa: entry.id)` para que también cuente el atajo ⇧⌘R (hoy cuenta el
  botón de la burbuja).
- **pasos (TLSOnboarding):** cada paso con su `BotonSaberMas(seccion: "paso-\(paso.rawValue)")`. El paso 8 («Primer
  recorrido») empieza el tutorial con `await TutorialEventos.empezar(.tuEmpresa, empresa: id)` y puede leer cómo va con
  `TutorialEventos.estado(.tuEmpresa, empresa: id)`; los hitos llegan solos a `EstadoPuestaEnMarcha.recorrido`. Para
  «Repasar la puesta en marcha» del ejemplo, poner `ControladorTutorial.repasarPuestaEnMarcha = { sesion in … }` al
  arrancar (abre la ventana de la puesta en marcha en modo repaso).
- **ordenar (TLSUI/Importar):** `ImportarMulticaHoja` ya está hecha y probada; el paso «Ordenar» (por herramienta: todo /
  lo activo / nada) la puede abrir tal cual o adoptar su modelo (`ModeloImportarMultica`). Si se mueve de fichero, que
  conserve el `init(sesion:)`.
- **F4 (asistentes):** al abrir el asistente con ⌘J, `TutorialEventos.registrar(.asistenteAbierto, empresa:)`; al pausar y
  reanudar, `.asistentesPausados` y `.asistentesReanudados`. Entonces quitar `llegaConLosAsistentes` de esos dos hitos.
- **por confirmar con el programa de Multica real (no se lanzó):** la orden de perfiles (`profile list --output json`) y la
  forma de `workspace list`. Si difieren, se cambia solo `OrdenMultica.argumentos` y `LecturaMultica`.

### importador

- **motor / pasos (TLSOnboarding):** el `EjecutorClasificacion` de verdad, con `ClaudeProbe` como `LanzadorClaudeCode`
  (sesión efímera = `--no-session-persistence`, `jsonSchema: AIClassifier.esquema`, sin servidores ni herramientas,
  dentro del sandbox): `ejecutar(peticion:esquema:)` devuelve la salida (`structured_output` o `result`; las dos se leen).
  Solo con el consentimiento de la persona (el mismo `usarAsistente`). TLSImport no depende de TLSAgents a propósito.
  **Hecho (motor, 23/10):** `LanzadorClaudeCode` cumple `EjecutorClasificacion` (`Sources/TLSOnboarding/Motor/`), probado
  con el ejecutable falso; quien lo cree comprueba `usarAsistente`.
- **ordenar:** tras `aplicar`, `registrarOrdenar(ResumenOrdenar(pantallas:…, movidos: vista.mover, completadas:
  vista.propiedades, archivados: vista.archivar, verificados: r.verificacion.comprobados, planes: r.planes, texto:
  r.verificacion.texto), aplicado: true)`; guardar `r.mapa` con `MapaImportacion.guardar(en: estado de la carpeta, …)`
  (lo usa «Actualizar la copia»). «Deshacer» hasta el paso 3 con `ImportApplier.deshacer(planes:con:)`. Pasar el
  `MotorDeDominio` de la sesión a `aplicar` para que lo importado no dispare reglas.
- **núcleo (escritor, F1; no bloquea):** mover un fichero guarda una copia previa entera en `copias/` (el contenido no
  cambia): con muchos PDF sueltos dobla el espacio durante 30 días. Las carpetas enteras se mueven de una vez y no lo
  necesitan; los ficheros sueltos, sí. Propuesta: sin copia previa en `mover` (basta la huella). Y
  `LinkRefactor.validate` rehace el mapa de rutas por cada traslado (cuadrático con miles de traslados).
- **decisiones del importador (por si Manu prefiere otra cosa):** lo que no tiene pistas va a `Buzón/Por ordenar/`
  (confianza 0,2); el año mínimo de las fechas es hace diez años (el script original fijaba 2023); `ruta` de
  `Fechas de documentos.csv` relativa a Finanzas (como Ribera y el conversor; el script la escribía desde la raíz); las
  fichas que se mueven pasan a kebab (`Ana López.md` → `ana-lopez.md`, con el nombre en `aliases` si cambia lo que se
  ve); lo traído de fuera que no se podría volver a leer (propiedades rotas) no se trae y se dice; un `.key` pequeño
  cuenta como clave (las presentaciones de Keynote son grandes o paquetes).

### ordenar

- **integración (TLSUI fuera de `Importar/`):** en `Pantallas/AjustesPantalla.swift`, sección «Esta empresa», una línea
  `FilaActualizarCopia(sesion: sesion)` (sale solo en copias con carpeta real); y en el menú de la copia
  (`Shell/TLSScenes.swift`, `ComandosEmpresa`) «Actualizar la copia desde la real…» que abra `ActualizarCopiaHoja(sesion:)`
  en una hoja de la ventana de la empresa.
- **motor:** la cabecera de las pantallas del paso 2 enseña la explicación genérica del motor («Pongo cada cosa en su sitio
  sin borrar nada…»); la buena está en `PantallaOrdenar.explicacion` y hoy se pinta debajo. Pedido: que `ResumenOrdenar`
  lleve también las explicaciones (o que el motor tome la de `titulos` de un diccionario) para que la cabecera diga lo de
  cada pantalla.
- **pasos:** en las pantallas de ordenar el pie dice «Siguiente» y «Aplicar» está dentro de la vista previa (y de «Completar
  las fichas»); si se prefiere, el pie podría llamar a `ModeloOrdenar.aplicar()` cuando el título sea «Vista previa». Al
  cerrar la ventana, `ConexionOrdenar.olvidar(vaultID)` libera el modelo del paso. «Dejarlo para más tarde» es vuestro
  «Saltar este paso».
- **banco (núcleo F2, importante para la copia de G3 de Manu):** con un `Registros/emitidas.csv` de columnas G3
  (`id,fecha,cliente,concepto,importe`, como el de la fixture `EmpresaMinima`), «Cargar en preparación» añade las filas
  pero la segunda vez `LegacyMovementsImporter.preparar()` las vuelve a dar como nuevas («5 nuevos · 0 ya cargados»): se
  podrían duplicar los 71 movimientos. Con los registros de la v2 (Ribera) funciona. Pedido: convertir antes esos registros
  o que `preparar()` lo detecte y no ofrezca cargar.
- **Decisiones del rol ordenar (por si Manu prefiere otra cosa):** lo ya en su sitio sale plegado en «Ya en su sitio»; el
  corte de «lo activo» propuesto es el 1 de enero del año pasado; «Es privado» de un bloque solo vale para esta
  importación (no se escribe en `privado:` de `.tls/config.yaml`; eso es del paso 0); el «Deshacer» del paso deshace
  también los movimientos heredados y las tareas de calidad creadas aquí; tras aplicar, el mensaje «312 de 312» va solo en
  su pantalla; la IA solo aparece si hay consentimiento (`usarAsistente`) y Claude, y aun así pide un sí explícito.

### pasos

- **integración (App y TLSUI, para el integrador):** declarar `OnboardingEscena(entorno: e)` en la app con
  `e.app = <el AppModel de TLSScenes>` y `e.instalarEjemplo = { try await InstaladorEjemplo().instalarOAbrir(en: model).entrada }`.
  Para eso TLSUI tiene que dar acceso a los dos: el `AppModel` de `TLSScenes` (p. ej. `TLSScenes(model:)` o un
  `AppModel.compartido`) e `InstaladorEjemplo.instalarOAbrir` público (o un `AppModel.abrirEjemplo()`). Sin esto todo
  funciona: se usa el registro, «Aplicar» abre su propio escritor (si la empresa está abierta en otra ventana, el escritor
  dice que otra ventana la tiene) y «Ver un ejemplo» abre el selector.
- **TLSUI (quitar duplicados):** hacer públicos `FolderAccess.check`, `FolderPanels` (`chooseCompanyFolder`,
  `choosePrivate`) y, si se quiere, `PermissionRecoveryView` e `ICloudExplanation`; entonces `AccesoCarpeta.comprobar` y
  `PanelesDelSistema` (TLSOnboarding) pasan a llamarlos. Hoy son una copia pequeña (abrir la carpeta sin listarla y el
  panel limitado a la carpeta de origen).
- **motor (TLSCore):**
  - con la carpeta recién creada («Empiezo de cero»), `ContextoCarpeta` la ve organizada y premarca `.etapa(a)` con la
    etapa calculada (1), que tapa lo contestado en las preguntas de etapa (`etapaDeArea` mira primero `.etapa(a)`). En
    pasos se guarda también `.etapa(a)` al contestar la cadena de etapa (`sincronizarEtapa`); pedido: premarcar
    `.etapa(a)` solo en la ruta de la copia de G3, o que `etapaDeArea` mire antes las respuestas de `etapaPregunta`;
  - no hay forma de olvidar una respuesta: al cambiar la carpeta de origen, lo privado contestado era de la otra; pasos lo
    resuelve con `privadasPorConfirmar`. Pedido: `olvidar(_ id:)`;
  - concordancia: «¿Cómo funciona hoy las ventas?» (y las finanzas) → «¿Cómo funcionan hoy…?» en `CatalogoPreguntas`;
  - `.modo` no llega premarcado sin carpeta: pasos pide elegirlo antes de copiar («Elige cómo quieres trabajar con ella»).
    Si se prefiere, premarcar «Trabajar sobre una copia (recomendado)».
- **ordenar (hecho):** al cerrar la ventana, `ConexionOrdenar.olvidar(vaultID)`. El pie sigue diciendo «Siguiente» en sus
  pantallas (su «Aplicar» va dentro de la vista previa, como pidió).
- **Decisiones del rol pasos (por si Manu prefiere otra cosa):** «Ver sin tocar» registra y abre la carpeta con un solo
  botón (no tiene más pasos); «Ver un ejemplo» también; la bienvenida no se puede saltar; «Saltar este paso» es `omitir`
  y se puede volver con «Volver a mirarlo»; repasar (el ejemplo) solo mira: no escribe ni marca nada; en el paso 7 Claude
  Code se busca al llegar (PATH de la shell y `claude --version`, sin consultas) y «Probar» hace una consulta mínima en el
  sandbox (0,05 USD como mucho); Mail, Calendario, Otros programas y Avisos quedan en «Ahora no» hasta la próxima versión;
  «Trabajar con la ventana cerrada» solo guarda la elección; la casilla «Incluir Archivo» de la copia, como en el arranque.

### integración (respuesta a lo pedido)

- **motor › integración (App, Launcher, Hoy, lint)**: hecho (ver «Integración»).
- **motor › lectura de `vocabulario:`**: **pendiente**. El paso 3 lo escribe; enseñarlo en pantalla cambia los nombres
  de bases, pestañas y relaciones en muchos sitios a la vez. Se deja para F4 (un `Vocabulario` leído por la sesión que
  usen todas las vistas), para no tener pantallas que digan «Casos» y otras «Oportunidades».
- **motor › diccionario (SISTEMAS §1.5)**: `areas_activas`, `## Encuadre` y `declarada: a medias | PENDIENTE` siguen como
  los dejó el motor; falta anotarlos en el diccionario de la propuesta (lo decide Manu).
- **tutorial › Shell**: `EscenaManual()`, `ComandosAyuda(model:)` y `.vistaEnFinder` en `revealInFinder`: hecho.
- **tutorial › F4**: ⌘J y pausar/reanudar siguen «Llega con los asistentes».
- **tutorial › Multica real**: sin comprobar contra el programa de verdad (no se lanza en pruebas).
- **importador › núcleo**: sin copia previa al mover y `validate` lineal: hecho. **ordenar**: hecho por su rol.
- **ordenar › integración TLSUI**: `FilaActualizarCopia` en Ajustes y la entrada del menú: hecho. **motor**: las
  explicaciones de cada pantalla en la cabecera: hecho. **banco**: los registros de G3 ya no duplican: hecho.
- **ordenar › pasos (opcional)**: el pie sigue diciendo «Siguiente» en las pantallas de ordenar; «Aplicar» va dentro de
  la vista previa (como está probado).
- **pasos › integración**: `OnboardingEscena(entorno:)` con el `AppModel` y el ejemplo: hecho. **TLSUI (duplicados)**:
  hecho (`PermissionRecoveryView` e `ICloudExplanation` siguen siendo internas: la bienvenida tiene las suyas, con
  Mosaico v2 y casi el mismo texto, y pasos propios como «Elegir otra carpeta»). **motor**: etapa, `olvidar`, concordancia y `.modo` premarcado: hecho.

