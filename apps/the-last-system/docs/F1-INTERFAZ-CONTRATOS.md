# F1 · Interfaz: contratos entre roles

Cimientos de la interfaz de F1 con **Mosaico v2** (`docs/propuesta/DISENO-MOSAICO-V2.md`, aprobado). Este fichero es
el contrato para los cuatro roles de pantallas (fichas, bases, editor, visores), que trabajan en paralelo. Lo de F0 y
el núcleo de F1 siguen en `docs/F0-CONTRATOS.md` y `docs/F1-CONTRATOS.md`. Las firmas de aquí se pueden **ampliar**,
no cambiar; si hace falta cambiar una, se pide en «Cambios pedidos» (al final).

## 1. Propiedad de ficheros en la fase de pantallas

Cada rol **solo** edita lo suyo. Si necesitas algo de otro, créalo en tus ficheros con una extensión o anótalo en
«Cambios pedidos». Si la compilación falla por ficheros que no son tuyos (otro rol está a medias), espera un par de
minutos y vuelve a compilar; no los toques.

| Rol | Ficheros |
|---|---|
| fichas | `Sources/TLSUI/Fichas/**`, `Sources/TLSUI/Relaciones/**`, `Sources/TLSUI/VistaPrevia/**`, `Sources/TLSCore/Relaciones/**` y sus pruebas (`Tests/TLSUITests/Fichas/**`, `Tests/TLSCoreTests/Relaciones/**`) |
| bases | `Sources/TLSUI/Bases/**`, `Sources/TLSUI/Busqueda/**`, `Sources/TLSCore/Bases/**` y sus pruebas (`Tests/TLSUITests/Bases/**`, `Tests/TLSCoreTests/Bases/**`) |
| editor | `Sources/TLSEditor/**`, `Sources/TLSUI/Editor/**` y sus pruebas (`Tests/TLSEditorTests/**`, `Tests/TLSUITests/Editor/**`) |
| visores | `Sources/TLSVisores/**`, `Sources/TLSUI/Carpeta/**`, `Sources/TLSUI/Launcher/**` y sus pruebas (`Tests/TLSVisoresTests/**`, `Tests/TLSUITests/Visores/**`) |
| cimientos (hecho; nadie más lo toca en esta fase) | `Package.swift`, `project.yml`, `Sources/TLSDesign/**`, `Sources/TLSUI/{Shell,Navegacion,BarraLateral,State,Support,Pantallas}/**`, `App/**`, el resto de TLSCore, y las pruebas que ya existen en `Tests/TLSUITests/*.swift` |

Notas:
- Los targets de pruebas ya existen (`TLSUITests`, `TLSEditorTests`, `TLSVisoresTests`, `TLSCoreTests`): basta con
  crear ficheros en vuestra subcarpeta; nadie tiene que tocar `Package.swift`.
- `Sources/TLSCore/Relaciones/` y `Sources/TLSCore/Bases/` aún no existen: los crea su rol.
- Cada fichero provisional que os dejo empieza con `// PROVISIONAL (cimientos)` y dice qué falta. Su **`init` es
  contrato** con el enrutador (`Shell/PantallaDestino.swift`): se rehace el cuerpo, no la firma.
- Compilad con vuestra propia carpeta: `swift build --package-path Packages/TLSKit --scratch-path build/spm-f1ui-<rol>`
  (y `swift test` igual). Cero avisos nuevos.

## 2. Cómo está montada la ventana

- `TLSScenes` (`Shell/TLSScenes.swift`): selector de empresa, `WindowGroup(id: "vault", for: VentanaRuta.self)` con
  pestañas del Mac y `Settings`. Al arrancar registra las letras (`TLSFuentes.registrar()`) y llama a
  `AppModel.prepararEscritura()` (= `VaultRegistry.permitirEscrituraEnCopias()`).
- **Una `VaultSession` por empresa**, compartida por todas sus pestañas y ventanas (`AppModel.retenerSesion` /
  `soltarSesion`): un índice y un escritor. **Una `Navegacion` por pestaña de ventana** (camino, historial, recuerdos;
  se guarda en `@SceneStorage`).
- `ContenidoEmpresa` (`Shell/`): `NavigationSplitView` de dos columnas (barra lateral + detalle) con un
  `NavigationStack(path:)` tipado con `Destino`; ‹ › y migas en la barra de la ventana (en una franja bajo ella por
  debajo de 960 pt); «Buscar o hacer… ⌘K»; banner COPIA/EJEMPLO encima de cada nivel; aviso con «Deshacer» abajo.
- `PantallaDestino` (`Shell/`): el enrutador `Destino` → pantalla. Envuelve cada pantalla con el banner, el fondo y
  la comprobación «como mucho un destacado» (`tlsPantalla`).
- Atajos (menú **Ir**): ⌘[ Atrás, ⌘] Adelante, ⌘1–3 Hoy/Decisiones/Tareas, ⌘4–9 áreas, ⇧⌘B Todas las bases,
  ⇧⌘F Buscar en la carpeta; ⌘K paleta, ⌘O abrir rápido, ⌘T pestaña nueva, ⌥⌘I propiedades. ⌘↑ sube un nivel (con
  `onKeyPress` en el detalle: en un campo de texto sigue yendo al principio).

## 3. `Destino` y cómo navegar

```swift
public enum Destino: Hashable, Codable, Sendable {
    case hoy, decisiones, tareas, revisar, todasLasBases, asistentes, ajustes
    case area(AreaCode, pestana: String? = nil)
    case base(String, vista: String? = nil, contexto: VaultPath? = nil)   // id de colección, vista guardada, «Facturas de X»
    case ficha(VaultPath, pestana: String? = nil)                          // nota con tipo (contacto, factura…)
    case nota(VaultPath)                                                   // Markdown/texto/CSV sin molde de ficha
    case fichero(VaultPath)                                                // PDF, imagen, audio, vídeo, otros (R1)
    case carpeta(VaultPath? = nil)                                         // nil = toda la carpeta
    case busqueda(String)
}
```

- **Pestañas dentro de una pantalla** (`area`, `ficha`): el `String` es el **nombre visible** («Resumen»,
  «Oportunidades», «Notas»…). Las migas lo enseñan tal cual como pestaña de origen («Arquitectura Nexo · Oportunidades»).
- **A dónde lleva una ruta:** `sesion.destino(para: ruta)` (carpeta, ficha si `NoteKind.abreComoFicha`, fichero si
  `TipoFichero.de(extension:).esVisor`, si no nota). Puro: `Destino.para(_:tipo:esCarpeta:)`.
- **Bases:** los `id` de colección son los de `BaseConocida.deSerie` (24, §4.2): `contactos`, `empresas`,
  `oportunidades`, `servicios`, `propuestas`, `reuniones`, `proyectos`, `planes-de-entrega`, `incidencias`, `tareas`,
  `facturas`, `cobros`, `gastos`, `movimientos`, `contenidos`, `conversaciones`, `sistemas`, `activos`, `roles`,
  `decisiones`, `objetivos`, `rutinas`, `colaboraciones`, `borradores`. El rol de bases los mantiene; si añade una,
  la describe con `sesion.barraLateral.describirBase(_:)`.

### Navegar desde una vista

```swift
@Environment(\.navegar) private var navegar          // NavegarAccion de la pestaña
navegar(.ficha(ruta))                                 // .automatico: clic = entrar; ⌘ = pestaña detrás; ⇧⌘ = delante; ⌥⌘ = ventana
navegar(.base("facturas", contexto: empresa), modo: .entrar)
navegar(.todasLasBases, modo: .raiz)                  // raíz nueva (como la barra lateral)
navegar(destino, modo: .raiz(sembrar: [.ficha(r)]))   // desde ⌘K: migas sembradas con el camino natural (§2.1 regla 3)
navegar(destino, modo: .pestanaNueva)                 // menú «Abrir en pestaña nueva»
```

- Fuera de una vista (por ejemplo, en un modelo): `sesion.navegar(a:modo:)` (actúa en la pestaña con el foco).
- `@Environment(\.navegacion) var nav: Navegacion?` para lo demás:
  - `nav.cambiarPestana("Proyectos")`: cambia la pestaña de la pantalla actual **sin** paso de historial (§2.1 regla 2).
  - `nav.vistaPrevia = ruta`: enseña la vista previa flotante de la pestaña (barra espaciadora); `nil` la cierra.
  - `nav.hoja = .paleta` / `.abrirRapido`.
  - `nav.migas`, `nav.actual`, `nav.puedeIrAtras`…; `irAtras()`, `irAdelante()`, `subir()`, `volver(a:)`.
- **Sin bucles**: `entrar` en algo que ya está en las migas las recorta hasta ello. **Renombrar o mover**: si escribís
  con `sesion.escribir`, las migas y el historial se actualizan solos (`aplicarMovimientos`).

### Recordar desplazamiento, filtros y selección (criterio §11.1)

- `ContenedorPantalla(destino:) { … }` (`Navegacion/`): `ScrollView` con ancho máximo de 1.240 pt, márgenes de §1.10 y
  el desplazamiento recordado. Para otro `ScrollView`: `.tlsRecordarDesplazamiento(destino)`.
- Filtros, selección, búsqueda, vista, agrupación…: `RecuerdoPantalla` por pantalla y pestaña de ventana:
  ```swift
  let r = nav?.recuerdo(de: destino)                              // al aparecer
  nav?.actualizarRecuerdo(de: destino) { $0.filtros["estado"] = "Activo" }   // al cambiar
  ```
  Campos: `desplazamiento`, `ancla`, `filtros: [String: String]`, `seleccion: [String]`, `busqueda`, `extra`.
  Se guardan con la pestaña y vuelven al reabrir la app. La clave es el destino sin la pestaña de dentro.

### Vista previa (§2.5)

`VistaPreviaPopover(ruta:sesion:)` (rol fichas) es la tarjeta. El disparo al pasar el puntero 0,6 s lo pone el rol de
fichas (con `TLSMovimiento.esperaVistaPrevia`); el modo elegido está en `AppModel.modoVistaPrevia` (`.alPasar` por
defecto, `.soloEspacio`, `.conComando`). Con el teclado: `nav.vistaPrevia = ruta` (el armazón ya la enseña arriba a la
derecha y la cierra con Esc). **Nunca escribe y nunca enseña lo privado** (`sesion.esPrivado`).

## 4. Cómo leer

Todo en `VaultSession` (`State/VaultSession+Lectura.swift`), fuera del hilo principal donde hace falta:

| API | Qué da |
|---|---|
| `LectorNota(ruta:sesion:)` + `.task(id: sesion.revision) { await lector.cargar() }` | La lectura de una pantalla: `nota: NoteSnapshot?` (contenido, propiedades, «Enlazan aquí», estilo), relee cuando cambia y reintenta iCloud (`sinLlegarDeICloud`, `reintentar()`) |
| `await sesion.leer(ruta)` | Una lectura suelta (`NoteSnapshot`) |
| `sesion.resumen(de:)` | `NoteSummary` del índice (título, tipo, área, privado, fecha). Instantáneo |
| `sesion.titulo(de:)`, `sesion.nombre(de: Destino)`, `sesion.simbolo(de:)` | Nombres e iconos (migas, historial, pestañas) |
| `await sesion.abrirRapido(texto)`, `await sesion.buscar(texto)` | Por nombre y texto completo, **sin lo privado** |
| `sesion.enlazanAqui(ruta)`, `sesion.resolverEnlace(_:desde:)` | Enlaces |
| `await sesion.instantanea()` | `VaultSnapshot` de toda la carpeta (para bases, relaciones inversas, plantillas, `TaskStore`, `LinkRefactor`). **Incluye lo privado**: filtrar con `sesion.esPrivado(_:)` antes de enseñar en bases, ⌘K o vistas previas |
| `sesion.areas`, `sesion.area(_:)`, `sesion.estructura` | Áreas (`AreaSummary`) y `VaultLayout` |
| `sesion.revision`, `sesion.ultimasCambiadas` | Sube con cada lote aplicado (de fuera o escrito por la app); `ultimasCambiadas` vacío = puede haber cambiado todo |
| `sesion.url(for:)`, `sesion.revealInFinder(_:)` | URL de una ruta (para visores) y Finder |
| `sesion.recientes` | Lo último abierto (sin privado) |

El índice es la vía rápida (menos de 100 ms por nivel, §7.2); `instantanea()` lee la carpeta entera: hacedla una vez
y en segundo plano, nunca al pintar.

## 5. Cómo escribir

**Toda** escritura en la carpeta pasa por `CommandBus` a través de la sesión. Nunca `FileManager`/`write(to:)` sobre
la carpeta; nunca se borra (retirar = `Archivo/`); todo se puede deshacer.

```swift
try await sesion.escribir(.cambiarPropiedades(ruta, poner: [Property(key: "estado", value: .text("Activo"))], quitar: []),
                          aviso: "Jorge pasa a Activo")            // aviso «… · Deshacer» y ⌘Z
let nota = try PlantillaMotor(snapshot: foto, registro: …).preparar(peticion)
try await sesion.escribir(plan: nota.plan, aviso: "Creé la reunión del 14 oct")   // planes compuestos: todo o nada
```

- Firma: `Autor.persona(sesion.persona)` (Ajustes › Tú; por defecto «Manu»). Los planes que preparéis vosotros
  (`PlantillaMotor`, `LinkRefactor.Opciones(autor:)`, `TaskStore`…) deben llevar `sesion.autor`.
- `aviso`: texto del aviso; `nil` = la descripción del cambio; `""` = sin aviso. `deshacer`: un `UndoManager`
  concreto; por defecto, el de la pestaña con el foco. ⌘Z llama a `CommandBus.deshacer` **solo** si ese plan sigue
  siendo el último de la carpeta (si no, avisa).
- Resultado: `WriteResult`. Un **conflicto no lanza**: devuelve `.conflicto(_)`, deja la tarjeta en «Revisar» y avisa.
  Los errores (`WriteError`, con texto llano) se avisan y se relanzan.
- Si escribís por otro camino (`LinkRefactor.aplicar(preview, con: bus)`), usad `sesion.bus` y después
  `sesion.registrarDeshacer(resultado, descripcion:aviso:)`. Mejor: comprobad `preview.esSeguro` y
  `sesion.escribir(plan: preview.plan)`.
- `sesion.puedeEscribir` / `sesion.modoEscritura` (`.escribe`, `.soloLectura(.carpetaReal | .elegido | .noSePudo(_))`):
  en solo lectura, los controles de editar salen desactivados **con el motivo** (`motivo.texto`). La carpeta real nunca
  escribe; una copia o el ejemplo pueden pasar a solo lectura y volver (pie de la barra lateral y Ajustes).
- «Revisar» (`Pantallas/RevisarPantalla.swift`): `sesion.tarjetas` (conflictos de edición y recuperación, duplicados,
  iCloud) y `sesion.textoRecuperacion`; se resuelven con `sesion.resolver(_:eleccion:)`,
  `descartarDuplicado(_:quedarmeConLaRepetida:)` y `resolverICloud(_:quedarmeCon:)`. Hoy enseña «Revisar» si
  `sesion.hayQueRevisar`. El editor que combine versiones usa `resolver(t, eleccion: .combinada(texto))`.

## 6. Huecos: tipos que el enrutador ya usa

| Destino | Tipo (fichero) | `init` | Rol |
|---|---|---|---|
| `.ficha` | `FichaPantalla` (`TLSUI/Fichas/FichaPantalla.swift`) | `init(ruta: VaultPath, pestana: String?, sesion: VaultSession)` | fichas |
| (vista previa) | `VistaPreviaPopover` (`TLSUI/VistaPrevia/VistaPreviaPopover.swift`) | `init(ruta: VaultPath, sesion: VaultSession)` | fichas |
| `.todasLasBases` | `TodasLasBasesPantalla` (`TLSUI/Bases/`) | `init(sesion: VaultSession)` | bases |
| `.base` | `BasePantalla` (`TLSUI/Bases/`) | `init(id: String, vista: String?, contexto: VaultPath?, sesion: VaultSession)` | bases |
| ⌘K | `PaletaBusqueda` (`TLSUI/Busqueda/`) | `init(sesion: VaultSession)` (hoja de la pestaña; cierra con `@Environment(\.dismiss)`) | bases |
| `.busqueda` | `ResultadosBusquedaPantalla` (`TLSUI/Busqueda/`) | `init(consulta: String, sesion: VaultSession)` | bases |
| ⌘O | `QuickOpenSheet` (`TLSUI/Busqueda/`, de F0) | `init(session: VaultSession)` | bases |
| `.nota` | `NotaEditorPantalla` (`TLSUI/Editor/`) | `init(ruta: VaultPath, sesion: VaultSession)` | editor |
| `.carpeta` | `CarpetaPantalla` (`TLSUI/Carpeta/`) | `init(carpeta: VaultPath?, sesion: VaultSession)` | visores |
| `.fichero` | `VisorFicheroPantalla` (`TLSUI/Carpeta/`) | `init(ruta: VaultPath, sesion: VaultSession)` | visores |
| selector | `LauncherView` y hojas (`TLSUI/Launcher/`, de F0) | — (abre con `openWindow.abrirEmpresa(id)`) | visores |
| `.hoy`, `.decisiones`, `.tareas`, `.area`, `.revisar`, `.asistentes`, `.ajustes` | `Pantallas/*` | — | cimientos (F2 las llena) |

Targets nuevos:
- **`TLSEditor`** (depende solo de `TLSDesign` y `swift-markdown`; no conoce TLSCore). Provisional:
  `EditorTextoMarkdown(texto:soloLectura:)` y `SeccionesMarkdown.titulos(_:nivel:)`. Recibe y devuelve texto; quien lo
  usa (`TLSUI/Editor`) guarda con `sesion.escribir(.guardarNota(ruta, base:, texto:))`.
- **`TLSVisores`** (depende de `TLSDesign`; PDFKit, AVKit, QuickLookUI). Hay: `TipoFichero` (`texto`, `pdf`, `imagen`,
  `audio`, `video`, `otro`; `de(extension:)`, `esVisor`, `simbolo`, `nombre`) —el enrutador lo usa para decidir entre
  `.nota` y `.fichero`; se puede ampliar sin cambiar los casos— y el provisional `VisorFichero(url:tipo:)`. Recibe una
  URL ya resuelta por TLSUI; nunca escribe en el fichero; descargar de iCloud solo al abrir.

De F0 quedan, movidos a la carpeta de su rol y adaptados lo justo: `Editor/{VisorNota (antes NoteViewer),
NoteInspector, SourceTextView, MarkdownStyler, MarkdownSpans}`, `Carpeta/FolderBrowserView`,
`Busqueda/{CommandPaletteSheet, QuickOpenSheet, FolderSearchView}`. Ahora elegir en una lista no abre (cada apertura
entra un nivel): abre doble clic o ↩. `session.open(ruta)` de F0 navega (entra un nivel en la pestaña con el foco).

## 7. TLSDesign: Mosaico v2

- **Color**: `TLSPaleta` (§1.2–§1.6: `fondo`, `superficie`, `superficieElevada`, `bandeja`, `cabecera`,
  `subtituloCabecera`, `sobreColor`, `texto`, `textoSecundario`, `separador`, `bordeControl`, `velo`, `principal` y
  `principalHover/Pulsado/Suave`, `sobrePrincipal`, `enlace` (siempre subrayado), `desactivadoRelleno/Texto`,
  `violeta*`, `chispa`, `anillo`, `chispaTexto`, `bien`, `atencion`, `mal`, `sinDato`, `glifo`, `borde1/2`). Cada uno
  es un `TLSColor` con claro, oscuro y sus variantes con «Aumentar contraste» (§1.8): `.color` (SwiftUI), `.ns`
  (AppKit), `.valor(oscuro:contraste:)`. Áreas: `TLSArea` (`tinta`, `relleno`, `glifoSobreBlanco`, `simbolo`);
  `AreaCode.tlsArea` en TLSUI. Estados: `TLSEstado` (`simbolo`, `color`, `tinte`, `palabra`). Contraste:
  `TLSContraste`, `TLSParejas.todas` (las pruebas comprueban todas con WCAG).
- **Letra**: `TLSTipo` (§1.9: `cifraHoy`, `cifraGrande`, `cifraMedia`, `tituloPantalla`, `tituloSeccion`,
  `tituloModulo`, `lectura`, `interfaz`, `interfazMedia`, `interfazFuerte`, `secundario`, `rotulo`, `cifraFila`,
  `codigo`, `textoPlano`). Úsalos con `.tlsTexto(TLSTipo.lectura)` (aplica tamaño × escala del texto 85–200 %,
  interlínea, espaciado y mayúsculas). `TLSFuentes` (registro, `ctFont`), `TLSEstiloTexto` (`nsFont`, `font`).
- **Medidas**: `TLSEspacio` (base 4, `margenPantalla(ancho:)`, `entreMosaicos`), `TLSRadio`, `TLSAltura`
  (`objetivoMinimo` 28, `botonPrincipal` 44, filas 36/44/32/28), `TLSAncho`, sombras `.tlsSombra(.uno/.dos, …)`,
  `TLSMovimiento` (entrar nivel, pestaña, muelle, espera de la vista previa, duración del aviso; `si(_:reducir:)`).
- **Componentes**: `CabeceraAzulNoche` (= `CabeceraPantalla`; con `EstadoCabecera`, `OpcionEstado`, `DatoClave`,
  `AvatarCabecera`), `Destacado` (+ `CifraDestacada`, `DestacadoVacio`; uno por pantalla), `Mosaico` +
  `MosaicoLayout` (+ `.tamanoMosaico(_)`), `PastillaEstado`, `InsigniaAviso` (siempre con palabra), `PuntoNovedad`,
  `Chip` (con «×» de 28 pt), `Tecla`, `Rotulo`, `IconoArea` (24/32, con `simbolo` para bases), `IconoTipo`,
  `Monograma`, `FilaLista` (+ `EstiloFila`), `VacioExplicado`, `Aviso` + `AvisoDeshacer` + `.tlsAviso($aviso)`,
  `PestanasCapsula` (+ `PestanaCapsula`; contador, urgente, insignia, «Más», ⌃1–⌃9), botones `.tlsBoton(.principal |
  .secundario | .sobreCabecera | .sobreDestacado | .enlace | .discreto)` y `BotonPrincipal(_:motivoDesactivado:)`,
  `BotonSecundario`; foco `.tlsAnilloFoco(_:radio:)`, `.tlsFocoPropio(radio:)`, `.tlsSobreColor()`; raíz de
  pantalla `.tlsPantalla(_:)` (avisa en depuración si hay más de un destacado).
- Los nombres de F0 (`TLSTokens.marca`, `fondo`, `superficie`, `Tipo.*`, `tlsPrimaryButton()`, `Badge`, `InfoBanner`…)
  siguen compilando con valores de Mosaico v2; el código nuevo usa lo de arriba.

Reglas que vigilan las pruebas: todas las parejas de §1 con WCAG (`MosaicoDesignTests`); el magenta
(`chispa`/`anillo`) solo en foco, insignia y punto (lint de fuentes); textos sin jerga (glosario de `CorreccionesUITests`
sobre `TLSUI` y `TLSDesign`: nada de vault, yaml, hash, run, issue…).

## 8. Barra lateral (API para el rol de bases y para F2)

`sesion.barraLateral: BarraLateralModelo` (se guarda por empresa en `Application Support/…/<id>/barra-lateral.json`):
- Bases: `fijarBase(id, deshacer:)`, `desfijarBase(id, deshacer:)`, `estaFijada(id)`, `describirBase(BaseConocida)`,
  `base(id)`; `mostrarEnBarra(destino)` («Mostrar en la barra lateral» de una miga raíz).
- Datos a la derecha o debajo de cada fila: `datos[.base("contactos")] = DatoFilaBarra(derecha: "16")`;
  `DatoFilaBarra(debajo:atencion:insignia:palabraInsignia:atenuado:)` (Decisiones con insignia magenta, «2 quietas» en
  Atención…). Las áreas ya llevan su estado de `Área.md`.
- Edición: mantener pulsado 0,4 s o «Editar»; arrastrar para ordenar (a la derecha, dentro), arrastrar fuera de la barra
  o a «Ocultos» para ocultar, ⌥⌘↑ ⌥⌘↓ ⌥⌘→ ⌥⌘←, menú contextual y acciones de VoiceOver con los mismos nombres; Deshacer
  con ⌘Z y en el aviso. Hoy no se oculta.

## 9. Pruebas y capturas

- `swift test` del paquete: 412 pruebas al cerrar cimientos (356 de antes + 56); 565 al cerrar la integración (las de
  capturas se saltan sin `TLS_CAPTURAS`).
- Capturas fuera de pantalla (sin abrir la app): `TLS_CAPTURAS=<carpeta> swift test … --filter CapturasTests`
  (`Tests/TLSUITests/CapturasTests.swift`) deja PNG en claro y oscuro de la galería de componentes, Hoy, un área, una
  ficha, Revisar, Todas las bases y la barra lateral (las de cimientos están en `build/capturas-f1ui-cimientos/`, fuera
  de git). Para vuestras pantallas, copiad el patrón (`capturar(_:…)` es
  `async`: deja correr las tareas del actor principal). La barra lateral dentro del `NavigationSplitView` sale en
  blanco en estas capturas (el panel flotante de macOS no se pinta fuera de pantalla); suelta se ve bien.
- Sesión de prueba con escritura: `SesionEscrituraTests.entorno(clase:escritura:)` copia Ribera a una carpeta temporal
  y `VaultSession(entry:estado:)` deja todo el estado (índice, diario, cerrojo, barra) fuera de la carpeta.

## 10. Decisiones de cimientos (para tenerlas en cuenta)

- **Letras en el paquete** (`Sources/TLSDesign/Recursos/Fuentes`, registradas con `CTFontManagerRegisterFontsForURL`
  y alcance de proceso), no en `App/Recursos/Fuentes`: así funcionan igual en la app y en `swift test`. Licencias y
  huellas en `docs/PROCEDENCIA.md`.
- **DM Sans no trae cifras tabulares** (sin `tnum` y con cifras proporcionales). `cifraFila` usa las cifras tabulares
  de la letra del sistema; Space Grotesk sí las trae (cifras grandes). Si Manu prefiere Space Grotesk también a 13 pt,
  es cambiar `TLSTipo.cifraFila`.
- **«Aumentar contraste»**: se resuelve con `bestMatch` y las apariencias de accesibilidad (§7.8). `NSAppearance(named:)`
  no deja crearlas, así que las pruebas comprueban los valores de contraste con `valor(oscuro:contraste:)`.
- **Color de acento** de la app = azul noche (`App/Assets.xcassets/AccentColor`), para los controles del sistema.
- `NoteKind` tiene los 47 `tls_type` de las plantillas (+ `note`, `csv`, `other`); `VaultIndex.schemaVersion` = 2 (un
  índice de antes se rehace solo). `AreaCode.colorHex` pasa a los rellenos de Mosaico v2.
- Pestaña nueva con ⌘clic: «detrás» se consigue volviendo a seleccionar la pestaña de origen al crearse la nueva.
  `openWindow.abrirEmpresa(id)` trae delante la ventana que ya tenga esa empresa; ⌘T abre otra pestaña.

## 11. Bases y ⌘K (rol de bases, 22/10; ampliado el 23/10)

Lo que pueden usar los demás roles y F2. Datos y reglas en `Sources/TLSCore/Bases/` (sin interfaz, probado con
Ribera); pantallas en `Sources/TLSUI/Bases/` y `Sources/TLSUI/Busqueda/`.

- **Catálogo:** `CatalogoBases.deSerie` (las 24 de §4.2, mismos `id` que `BaseConocida`), `coleccion(_:)`,
  `coleccion(paraTipo:)`, `grupos` (Comunes y 1–6), `vistasDeSerie(_:)` (Oportunidades: Abiertas · Por cerrar este mes
  · Ganadas). `ColeccionBase`: `fuentes` (`.fichas([NoteKind])` o `.filasCSV(carpeta:nombre:clave:soloSi:)`), `hogar`,
  `notaIndice`, `frase`, `vista`, `vistas`, `columnas` (`ColumnaBase`: `clave`, `etiqueta`, `TipoColumna`, `alias`,
  `opciones`, `relacionCon`, `Calculo`), `agruparPor`, `pestanas` (`PestanaBase` + `FiltroPestana`), `cerrados`,
  `plegadas`, `fechaCalendario`, `cronograma`, `plantilla` / `motivoSinCrear`, `creaConTitulo`, `modulo`.
- **Leer:** `LectorBases(service:ajustes:persona:)` → `leer(_:) -> DatosBase` y `leerTodas()`. `DatosBase`: `filas`
  (`FilaBase`, **nunca lo privado** ni plantillas ni `Archivo/`), `indice` (`NotaIndiceBase`: vista, `agrupar_por`,
  `pestanas_por`, frase), `cifras` (3), `urgente` (`AvisoBase`), `abiertas`, `ultimoCambio`, `pie`, `apagada`,
  `pestanas`, `vistaPorDefecto`. `AjustesBases.leer(root:)` (módulos de `.tls/modulos.yaml` y `hoy:` de la demo).
  Índice: `VaultService.fichas(deTipos:)`, `todasLasFichas()`, `ficherosCSV(llamados:bajo:)` → `FichaIndexada`
  (incluyen lo privado: filtrar con `resumen.privado`).
- **Vista:** `ConfigVista` (vista, pestaña, `FiltroBase`, agrupar, `OrdenBase`, columnas, anchos, densidad, tamaño de
  galería, fecha del calendario, plegados), `VistaGuardada`, `MotorVista` (`filas`, `cuenta`, `coincide`,
  `resaltar`, `sugerencias`, `pasa`, `ordenar`, `urgencia`, `agrupar` con subtotal). `AlmacenVistas` (hoy en
  `<estado>/vistas/<base>.json`; ver «Cambios pedidos»).
- **Escribir en la celda:** `EdicionCelda.valor(_:para:hoy:)`, `comando(_:_:valor:coleccion:)` (solo esa clave:
  `.cambiarPropiedades`; en un CSV, solo esa fila: `.guardarFila`), `motivoSoloLectura`, `lineaPrevista`,
  `opciones(_:fila:)`. `ReglaGanada.motivo(_:)`: una oportunidad no pasa a Ganada sin un cobro confirmado.
- **⌘K:** `CatalogoBusqueda.construir(_:)` y `buscar(_:limite:)` (número o código, título, otros nombres y
  propiedades; menos de 100 ms con 5.000 fichas) y, en TLSUI, `MotorPaleta.secciones(...)`.
- **En TLSUI:** `AlmacenBases.de(sesion)` (datos de las 24 bases y el catálogo de ⌘K, compartidos por las pestañas y
  al día con `sesion.revision`; pone los números de la barra lateral). Para abrir una base con su hoja «Nueva …»:
  `nav.actualizarRecuerdo(de: .base(id)) { $0.extra["nueva"] = "1" }` y navegar. `.base(id, contexto: ruta)` enseña
  solo las fichas que enlazan esa ruta y crea ya enlazado. `CreadorFichas.crear(coleccion:peticion:sesion:deshacer:)`
  crea con la plantilla (un plan, Deshacer, reintenta si pierde la carrera, «Completar la que hay» si ya existe).
- **23/10:** las celdas de relación abren `SelectorDeRelacion` (fichas) salvo lo que no se toca (con candado y
  motivo); clic derecho y «Ir a» del menú de la fila abren lo enlazado. Filas, tarjetas, la celda del título y los
  eventos del calendario llevan `.vistaPrevia(ruta:sesion:)` (puntero 0,6 s; en una fila de CSV, su documento:
  `FilaBase.rutaPreviaAlPasar`). «Editar descripción» edita la frase en la cabecera de la base y la guarda en la nota
  índice cambiando solo su primer párrafo (`NotaIndiceBase.cambiandoFrase(_:por:)`, `BaseModelo.guardarDescripcion`,
  `.guardarNota` por `CommandBus`, con Deshacer). El calendario tiene Mes y Semana (`EscalaCalendario`,
  `ConfigVista.escalaCalendario` opcional, `ColeccionBase.escalaCalendario`: Reuniones abre en semana): la semana va
  de 7 a 21 con `hora` y `duracion_min`, «Todo el día» para lo que no tiene hora y la línea «ahora» con
  `PuntoNovedad`. `FormatoBase.lunes(de:)`, `semana(_:)` y `hora(_:)`.

## 12. Integración final (23/10)

Une los cuatro roles. Lo nuevo que pueden usar F2 y siguientes:

- **TLSDesign:** `MarcaAhora(.horizontal | .vertical, palabra:)` (+ `MarcaAhora.color`, `.grosor`);
  `CabeceraAzulNoche(…, debajo:)`; `.tlsBoton(.enlace)` en blanco dentro de `.tlsSobreColor()`; `PestanasCapsula` pasa
  a «Más ▾» las pestañas que no caben (la elegida siempre se ve; ya no se desplaza a lo ancho). Todas las cápsulas son
  circulares.
- **Ventanas:** `AppModel.identificadorPestanas(_:)`, `ventanas(de:)` y `cerrarVentanas(de:espera:)`.
- **Navegación:** `Navegacion.inspector` (panel de propiedades por pestaña de ventana, guardado con ella). La pestaña de
  origen va en la miga de la que se salió («Jorge Martín · Proyectos › Trimestrales 2026», como en M2-Proyecto).
- **Escritura:** `.tls/vistas/<base>.json` por `CommandBus` (solo personas); deshacer un ajuste creado lo retira a
  `Archivo/Ajustes de la app/…`. `sesion.versionesParaCombinar(_:)` para «Combinar» en Revisar.
- **Lectura:** `sesion.resolverEnlace("[[factura.pdf]]", desde:)` encuentra adjuntos por su nombre en cualquier carpeta.
- **Cifras:** `FormatoBase.cifra/euros` enseñan «—» con NaN o infinito (antes se cerraba la app al convertir a entero) y
  `FormatoBase.numero("nan")` ya no es una cifra.
- **Pruebas nuevas** (`Tests/TLSUITests/Integracion/`): `RecorridoF1Tests` (recorrido completo con Ribera: §11.1, §11.4,
  §11.5, §11.10, renombrar, PDF, incrustación y el camino de la guía de Manu), `GlosarioTests` (lint del glosario sobre
  los cuatro módulos de interfaz, los textos que fabrica la app y lo que enseñan las 24 bases con Ribera),
  `FormasTests` y `CapturasF1Tests` (`make capturas`). En el núcleo, `EscrituraVistasTests`.
- **`make capturas`:** `scripts/capturas.sh` deja en `build/capturas/` 26 PNG (13 pantallas en claro y oscuro, con ⌘K y
  dos con «Aumentar contraste» desde la revisión final) y un `index.html`. La ventana se compone a mano (barra lateral + barra de la ventana + pantalla) porque el
  `NavigationSplitView`, la barra de herramientas y el `.inspector` no se pintan fuera de pantalla.

## 13. Revisión final (corrector, 23/10)

Aplica los hallazgos de las dos revisiones de F1 (diseño y accesibilidad; datos). Las 15 pruebas de la revisión de
datos (`Tests/TLSUITests/RevisionF1InterfazTests.swift`) ya no llevan `withKnownIssue` y quedan como regresión (16 con
la de ⌘Q); las de diseño están en `Tests/TLSUITests/Integracion/RevisionFinalTests.swift` (8).

**Datos (los 12 confirmados y 4 de los 5 probables):**
- **Cifras en celdas:** `EdicionCelda` rechaza desde mil billones (`EdicionError.demasiadoGrande`; antes `Int64(1e20)`
  cerraba la app). `FormatoBase.numeroEscrito(_:)` lee «1.235» y «15.000» como millares (lo escrito por una persona)
  y `FormatoBase.cifraParaEditar(_:)` enseña la cifra sin puntos en el editor de la celda. `FormatoBase.numero` (lo
  que se lee de la carpeta) no cambia. Un CSV solo escribe `true`/`false` si el valor es de verdad sí/no.
- **Secciones de la ficha:** «Editar» toma la huella (`FichaModelo.huellaSeccion`) y `guardarSeccion(_:texto:en:huella:)`
  devuelve `.guardada`, `.cambiadaFuera` o `.noSePudo`. Si cambió fuera, el borrador sigue abierto con «Cambió fuera»
  y «Ver diferencias…» (`DiferenciasVersiones`: quedarme, usar lo de fuera o combinar, con la huella de ahora).
- **Privado en el Archivo:** `VaultLayout.isPrivate` mira también `Archivo/<ruta>` y `Archivo/Conflictos|Duplicados/<ruta>`
  (núcleo). «Mover a…» avisa si algo sale de una carpeta privada (`CarpetaModelo.avisoSalePrivado`) y no deja mover la
  carpeta `Archivo` (`esLaCarpetaArchivo`).
- **Guardados pendientes:** `GuardadosPendientes.compartido` (editores abiertos, débiles) se vacía en
  `VaultSession.pasarASoloLectura` (`guardarPendientes()`) y en `TLSAppDelegate.applicationShouldTerminate` (⌘Q:
  `.terminateLater`, tope de 5 s).
- **Renombrar y Deshacer:** `VaultSession.registrarNavegacion(_:)` (lo hace solo `navegacionActiva`) y
  `aplicarMovimientos(_:)` llevan los movimientos a todas las pestañas y ventanas de la empresa y a Recientes;
  `deshacer(plan:)` aplica los de vuelta.
- **Memoria:** `VaultSession.close()` llama a `AlmacenBases.soltar` y `AlmacenRelaciones.soltar` (la sesión y la foto
  con lo privado ya no se quedan tras cerrar la empresa).
- **«Editar descripción»:** `NotaIndiceBase.frase/cambiandoFrase` solo toman un párrafo; si tras el título hay una
  lista, una consulta, un comentario o HTML, la frase se inserta tras el título y no se borra nada.
- **Arrastres:** `ArrastreCarpeta(empresa:rutas:)` y `ArrastreFila` («tls-fila:<empresa>:<id>», tablero, calendario,
  semana y tablero del proyecto): lo de otra empresa no se acepta al soltar.
- **«Hacer vista por defecto»** quita `agrupar_por` si no se agrupa.
- **Lecturas:** `NoteSnapshot.lectura` se numera al empezar a leer; `ModeloNotaEditor` descarta una lectura anterior a la
  última y las que empezaron antes de su último guardado; `LectorNota` descarta una lectura cancelada o más vieja.
- **Probables:** `AjustesBases.leerTexto` (sin enlaces ni iCloud) en las vistas guardadas, «Combinar» y
  `.obsidian/app.json`; `ResumenDeFicha` no enseña una oportunidad ni un rol privados; en `.tls/modulos.yaml` la línea
  propia de un módulo manda sobre `encendidos/apagados: […]`.

**Diseño y accesibilidad (P1 y P2 todos; P3 casi todos):**
- «Ahora» ya no se vacía con el destacado vacío (`ResumenDeFicha.quitandoLoDelDestacado`).
- Botón desactivado sobre la cabecera o el destacado: texto `desactivadoSobreColor` (blanco 85 %, 9,6:1 y 4,55:1) y
  borde `desactivadoSobreColorBorde`; sus parejas están en `TLSParejas`. La acción principal de la cabecera de la ficha
  mide 44 pt y, desactivada, dice al lado por qué. `EstiloContornoCabecera` mide 44 pt.
- `InsigniaAviso(…, enCapsula: true)`: palabra y número en la cápsula magenta («Por revisar 1»), en todas las pestañas.
- `PastillaEtapa(_:paso:de:)` (TLSDesign) y `PastillaDeEstado(valor:coleccion:)` (bases): Prospecto → Aceptada con
  cuatro puntos; Ganada en Bien; Perdida y Pausada sin dato. «Emitida» y «Propuesta» ya no son Atención.
- Barra de la base: con palabras y en dos líneas (`NivelBarra.dosLineas`); solo con iconos en ventanas muy estrechas.
  Iconos de §1.11 (Filtrar `line.3.horizontal.decrease.circle`, Agrupar `rectangle.3.group`, Columnas
  `slider.horizontal.3`; «Más» pasa a `ellipsis.circle`).
- Un solo «hoy»: `VaultSession.hoy` (`hoyCarpeta` de `.tls/config.yaml`); Hoy lo usa (`HoyPantalla.fechaLarga(LocalDate)`).
- Tabla en oscuro sobre `superficie`; eventos del calendario y la semana, y celdas de la Tabla, de 28 pt.
- Tablero del proyecto: tarjetas enfocables con Tab (anillo magenta, ↩ abre, espacio vista previa, ⌘← ⌘→ con la
  enfocada) y conmutadores en cápsula (`SelectorCapsula`). Vencidas con icono y la palabra «Vencida».
- Vistas de F0 (⌘O, inspector, crear copia, permisos, búsqueda en la carpeta) con `TLSPaleta.textoSecundario`.
- «Aumentar contraste»: `TLSApariencia.modo(de:)` mira también el ajuste del Mac (SwiftUI resuelve `Color(nsColor:)`
  solo con `colorScheme`; comprobado) y `TLSApariencia.contrasteForzado` lo fuerza en pruebas y capturas.
- P3: `Chip` con área lleva su icono; «La lleva: …»; cifras de la base a la derecha en Space Grotesk 24
  (`CabeceraAzulNoche(…, cifrasALaDerecha:)`, desde 760 pt); vistas guardadas con contador; línea magenta de hoy y
  leyenda «Hoy, lun 19 oct» en Fases del plan; «Mover a…» subrayado; la línea «>» de la ficha sin el estado
  (`FormatoFicha.sinEstado`); el nombre de la empresa en dos líneas en la barra lateral; «Como texto» en vez de «Texto
  fuente».

**Se quedan (con motivo):**
- Comprobar con la app abierta y el ajuste real «Aumentar contraste», el orden de Tab, ⌘clic, la vista previa al
  pasar el puntero, arrastrar, el `.inspector`, Quick Look y AVKit: no se puede abrir la app ni tocar ajustes del Mac
  (están en la guía, `docs/pruebas/F1.md` §8).
- Datos del ejemplo («importación desde G2 («DEV - Asesoría Ribera»)» en «Lo último» de 10 contactos, el PDF con
  «Telefon˜›a», `.tls/config.yaml` en el informe del Buzón): el ejemplo del repo no se toca en este rol.
- Para decidir: tras un guardado automático del editor, ⌘Z ya no deshace un cambio de propiedades anterior (avisa de
  que antes hay que deshacer el guardado, que no se puede deshacer desde ningún sitio).
- Capturas del lanzador, de la vista previa y del selector de relación (las de ⌘K y contraste ya están).

## Cambios pedidos

- **corrector final → núcleo/cimientos (hecho, 23/10):** `VaultLayout.isPrivate` con `Archivo/` (núcleo);
  `TLSAppDelegate.applicationShouldTerminate` (cimientos); en `VaultSession`: `close()` suelta los almacenes,
  `registrarNavegacion`/`aplicarMovimientos`, `hoy`/`hoyCarpeta`, `guardarPendientes()`, y `leer(_:)` numera al
  empezar; `TLSApariencia.modo(de:)` y `contrasteForzado` (TLSDesign); `AjustesBases.modulos` (prioridad de la línea
  propia); `FormatoBase.numeroEscrito`, `cifraParaEditar`, `cifraMaxima` y `EdicionError.demasiadoGrande`.

- **visores → fichas, editor y bases (22/10): API de `TLSVisores` (R1).** Estable; se puede ampliar.
  - Pantalla completa: `VisorFichero(url:tipo:pagina:descargaAutomatica:acceso:alCambiarPagina:)` elige el visor (PDF,
    imagen, audio, vídeo o Quick Look) y se ocupa de iCloud. PDF: `VisorPDF(url:pagina:alCambiarPagina:)` sobre
    `ControladorPDF` (`cargar(url:pagina:)`, `ir(aPagina:)`, `ajustarAncho()`, `ajustarPagina()`, `acercar()`,
    `alejar()`, `tamanoReal()`, `buscar(_:)` → `resultados`, `indice`, `copiarSeleccion(en:)`; nunca escribe).
    Imagen: `VisorImagen(url:)` (`ControladorImagen`). `ReproductorMedio(url:tipo:)` y `VistaQuickLook(url:)`.
  - **Editor:** el `contenido` de `BloqueIncrustado` es `ContenidoIncrustado(url:tipo:pagina:ancho:acceso:alAbrir:)`
    (sin franja: PDF compacto en la página de `#page=N` con ‹ › y «2 / 4», imagen ajustada a `|ancho`, reproductor
    o tarjeta con «Abrir»). Altos: `IncrustacionFichero.altoPorDefecto(tipo)` y `altoAmpliado(tipo, base:)`
    (`nonisolated`). `ReferenciaIncrustada.leer(_:markdown:)` lee `#page=N`, `#height=N`, `|300`, `|300x200`, `%20` y
    `<…>`. `IncrustacionFichero(url:referencia:titulo:acceso:alAbrir:)` es el bloque con su propia franja (para quien
    no tenga marco). Lo que está solo en iCloud no se descarga al pintar: sale «Descargar y abrir».
  - **Fichas:** `VistaPreviaPDF(url:pagina:titulo:alto:acceso:alAbrir:)` (la primera página o la indicada, cuántas
    páginas tiene y «Abrir») y `MiniaturaFicheroVista(url:tipo:pagina:lado:)` para cualquier fichero.
  - **Bases (Galería, F2):** `MiniaturaFichero.generar(url:tipo:pagina:lado:acceso:) async -> ImagenMiniatura?` (fuera
    del hilo principal; `nil` si no está en el Mac) y `MiniaturaFichero.paginas(dePDF:)`.
  - iCloud: `AccesoICloud` (`estado(de:)` sin abrir el fichero, `pedirDescarga(de:)`), `AccesoICloudSistema` (y
    `sinDescargar { }`), `DescargaICloud` (`comprobar`, `descargar`, `reintentar`, `fase`, `texto`) y
    `EstadoDescargaVista`. Mirar nunca descarga; solo abrir (acción de la persona).
  - `AccionesFichero` (`abrirEnVistaPrevia`, `mostrarEnFinder`, `abrirConLaDeSiempre`, `aplicaciones(para:)`) y
    `MenuAbrirCon(url:)`. `TipoFichero` ampliado (sin cambiar los casos): `de(nombre:)`, `seIncrusta`,
    `tieneMiniatura`, `conEste`; `TamanoFichero.texto(_:)`.
  - TLSUI: para abrir un PDF en una página, `VisorFicheroPantalla.abrir(ruta, pagina:, nav:, navegar:, modo:)` (deja la
    página en el recuerdo de `.fichero(ruta)`, `extra["pagina"]`, y navega). La URL sale de `sesion.url(for:)` y el
    destino de una incrustación de `sesion.resolverEnlace(_:desde:)`. Nunca pasar a una vista previa una ruta privada
    (`sesion.esPrivado`).
- **visores → cimientos (22/10, hecho en integración el 23/10):** declarar en `App/Info.plist` (`UTExportedTypeDeclarations`, conforma a `public.data`)
  el tipo `es.thelast.system.ruta-carpeta` (`UTType.tlsRutaCarpeta`), con el que se arrastran filas dentro de la
  Carpeta. Sin declararlo funciona dentro de la app, pero el sistema lo avisa en el registro.
- **visores → cimientos (22/10, hecho en integración el 23/10: era `Capsule()`, que en macOS 15 es de esquina continua y su
  borde se pinta con dos rayas en los extremos; ahora todas son `Capsule(style: .circular)` y `FormasTests` lo vigila):**
  en las capturas fuera de pantalla, `.tlsBoton(.secundario)` enseña dos rayitas
  verticales en los extremos de la cápsula (también en `componentes-claro.png` de cimientos). Revisar el `overlay` con
  `Capsule().strokeBorder` de `TLSBotonStyle` (puede ser solo de la captura).
- **visores → cimientos (22/10, hecho en integración el 23/10: `AppModel.cerrarVentanas(de:espera:)` y
  `AppModel.identificadorPestanas(_:)`, que usan la ventana, ⌘O de empresa y el selector):** «Reiniciar ejemplo» cierra las ventanas del ejemplo buscando
  `tabbingIdentifier == "empresa-<id>"` y espera a `AppModel.sesionAbierta(id) == nil`. Si cambia ese identificador,
  hay que cambiarlo en `Launcher/LauncherView.swift`; mejor aún, un `AppModel.cerrarVentanas(de:)`.
- **visores → fichas (22/10, hecho por fichas):** la Carpeta abre `nav.vistaPrevia` con la barra espaciadora también
  sobre ficheros (PDF, imagen). `VistaPreviaPopover` ya enseña `MiniaturaFicheroVista` cuando
  `TipoFichero.de(extension:).tieneMiniatura` y la ruta no es privada.
- **visores (23/10): estado al cerrar.** Sin cambios de API desde el 22/10. Ya usan `TLSVisores`: el editor
  (`Editor/AdaptadoresEditor.swift`), las fichas (`Fichas/FichasConcretas.swift`) y la vista previa. El ejemplo va en
  `Contents/Resources/Recursos/Ejemplos/Asesoria-Ribera` (comprobado en un `xcodebuild` sin firmar). Sigue pendiente
  de cimientos declarar `es.thelast.system.ruta-carpeta` en `App/Info.plist`.
- **bases → escritor/cimientos (22/10, hecho en integración el 23/10): vistas guardadas en la carpeta.** Ya se guardan en
  `.tls/vistas/<base>.json` por `CommandBus` (`PlanCompiler.esVistaGuardada`: un nivel, JSON, solo personas). Las de
  los datos de la app pasan con ellas al primer guardado; con la carpeta en solo lectura siguen en los datos de la app.
  Deshacer la primera vista la retira a `Archivo/Ajustes de la app/vistas/` (`VaultWriter.componentesVisibles`: en
  `Archivo/` no hay carpetas ocultas). Lo que pedía bases: `PlanCompiler.writableSettings` solo deja
  seis rutas fijas de `.tls/`, así que `.tls/vistas/<base>.json` da `rutaNoPermitida`. Cambio mínimo propuesto: en
  `PlanCompiler.checkAllowed`, admitir además `.tls/vistas/<nombre>.json` (un solo nivel, sin `..`, extensión `json`)
  solo a personas (`!isAgent`); `validate` ya comprueba que el JSON se lee. Mientras, las vistas van fuera de la
  carpeta, en `<estado>/vistas/<base>.json` (`AlmacenVistas`); cuando se permita, `BaseModelo.guardarVistas` pasa a
  `sesion.escribir(.crear(…) / .guardarNota(AlmacenVistas.rutaEnCarpeta(id), …))` y se copian las que haya.
- **bases → cimientos (22/10, hecho en integración el 23/10): números de las bases en la barra lateral.** Añadir `.tlsContadoresDeBases(sesion)`
  (en `TLSUI/Bases/AlmacenBases.swift`) a `ContenidoEmpresa`: una línea, los pide al abrir y con cada
  `sesion.revision`. Mientras no esté, se ponen al abrir «Todas las bases» o una base.
- **bases → cimientos (hecho por bases, 22/10): `VaultService.indiceAbierto`.** Tres líneas `internal` en
  `VaultService.swift` (junto a `summary(of:)`) para que `Bases/IndiceBases.swift` consulte el índice (tipos,
  propiedades en JSON y enlaces). Sin columnas nuevas: `VaultIndex.schemaVersion` sigue en 2.
- **bases → cimientos (22/10, hecho en integración el 23/10: `MarcaAhora(_:palabra:)` en `TLSDesign`, horizontal o
  vertical, con `MarcaAhora.color` y `.grosor` para la regla «hoy» del cronograma en Charts; la semana y el cronograma
  ya la usan): la línea de hoy en magenta.** §4.4 la pide magenta en el calendario y el cronograma,
  pero el lint solo deja el magenta en `TLSDesign` (`Foco`, `Pastillas`). Hoy va en azul noche; si se quiere magenta,
  un componente `LineaAhora` en `TLSDesign/Componentes/Pastillas.swift` y las bases lo usan. Desde el 23/10, la
  línea «ahora» de la semana empieza con `PuntoNovedad(palabra: "Ahora")` (magenta permitido) y sigue en el color
  del texto.
- **bases → fichas (hecho, 23/10):** las celdas de relación ya abren `SelectorDeRelacion` y las filas y tarjetas usan
  `.vistaPrevia(ruta:sesion:)`. Lo de debajo queda como historia.
- **bases → cimientos (23/10, hecho en integración el 23/10: `CabeceraAzulNoche(…, debajo:)`; «Editar descripción» es
  un enlace blanco bajo la frase y el campo se abre dentro de la cabecera, como en M2-Bases; `.tlsBoton(.enlace)` sobre un
  relleno de color va en blanco):** un hueco bajo el subtítulo de `CabeceraAzulNoche`. En M2-Bases, «Editar descripción»
  es un enlace bajo la frase y el campo se abre dentro de la cabecera. Sin ese hueco, el botón va en las acciones y el
  campo justo debajo de la cabecera, en `bandeja`. Propuesta: `init(…, @ViewBuilder debajo: () -> Debajo)` que se pinta
  tras el subtítulo (vacío por defecto); las bases lo usarían sin más cambios.
- **bases → fichas (22/10):** las celdas de relación de la Tabla están en solo lectura con «Cambiar…», que lleva a la
  ficha (allí está el selector). Cuando `SelectorRelacion` tenga una firma estable, la celda lo abre en su `popover`
  (`CeldaRelacion` en `Bases/CeldaBase.swift`). La vista previa de filas y tarjetas se abre con la barra espaciadora y
  con «Vista previa» del menú; el disparo al pasar el puntero 0,6 s, cuando exista el modificador de fichas.
- **fichas → todos (22/10): lo que exponen las fichas.** Estable; se puede ampliar.
  - Vista previa: `.vistaPrevia(ruta:)` (la sesión sale de la ficha que la contiene o de la empresa de la pestaña de
    ventana) y `.vistaPrevia(ruta:sesion:)` para pantallas fuera de una ficha (bases, búsqueda, carpeta). Puntero 0,6 s
    según `AppModel.modoVistaPrevia` (o con ⌘ pulsado), barra espaciadora con el foco en la vista (`nav.vistaPrevia`) y
    acción «Vista previa» de VoiceOver. `ruta` = `nil` no hace nada; lo privado no se enseña. Nunca escribe.
  - `VistaPreviaPopover(ruta:sesion:)` enseña también la miniatura de un PDF o una imagen (`MiniaturaFicheroVista`),
    como pidió visores.
  - **bases:** `SelectorDeRelacion(dueno:propiedad:sesion:)` dentro de un `popover` es el selector de §5.2 listo para
    la celda de relación: busca, crea al vuelo, confirma dentro (línea antes y después) y escribe una línea con
    Deshacer. Para la lista de lo relacionado de una ficha y el «Conectado con», `AlmacenRelaciones.de(sesion)`
    (foto y `GrafoRelaciones` compartidos por empresa, rehechos con `sesion.revision`).
  - TLSCore (`Sources/TLSCore/Relaciones/`): `EsquemaRelaciones` (quién guarda cada relación, §5.1; `definicion`,
    `guardadas(por:)`, `quienGuarda(apuntandoA:desde:)`, `canonica`), `GrafoRelaciones(snapshot:)` (`salientes`,
    `entrantes`, `relacionados(de:)` con `Relacionado.Via` directa/porCarpeta/indirecta, `destinos(de:propiedad:)`,
    `enlazanDesdeTexto`, `origenes`, `cobroConfirmado(oportunidad:)`), `EditorDeRelaciones` (`preparar(CambioDeRelacion)`
    → `RelacionPreparada` con el comando de **una línea**, `lineas.antes/despues` y `pideConfirmacion`; `colgantes`,
    `enCadena`, `crearYEnlazar`, `enlace(a:)`), `ProblemaDeRelacion`, `EstadosDeFicha` (estados por tipo, `abierta`,
    `esperaTuOK`, `urgencia`, `ordenar`), `PlanDeEntrega.leer` y `FasesDelPlan.delProyecto`, `ActividadDeFicha.leer`,
    `Responsables` (identificador estable ↔ nombre), `DiferenciaDeLineas.cambiadas`.
- **fichas → cimientos (22/10):** `.inspector` no se pinta en las capturas fuera de pantalla (sale un marco de
  colores, como la barra lateral dentro del `NavigationSplitView`); el panel suelto sí (`InspectorFicha(modelo:,
  desplazable: false)`, en `build/capturas/fichas/contacto-jorge-propiedades-*.png`, y puesto al lado de la ficha a
  mano en `contacto-jorge-con-propiedades-*.png`). Sin comprobar en la app.
- **fichas → cimientos (22/10, hecho en integración el 23/10: `Navegacion.inspector`, guardado con la pestaña;
  `sesion.showInspector` es ahora el de la pestaña con el foco y la ficha y la nota leen el de su propia pestaña):** el
  panel de propiedades de la ficha usa `sesion.showInspector` (⌥⌘I), que es de la
  empresa y no de la pestaña de ventana: abrirlo en una pestaña lo abre en todas. Si se quiere por pestaña, un
  `Navegacion.inspector` y la ficha lo lee de ahí.
- **fichas → cimientos (22/10, `MarcaAhora` ya existe; las fases siguen con el punto, que es lo que pide §3.4 en una
  pieza que no es una línea): la línea «hoy» en magenta** de las fases del plan (§3.4) es, como en bases, un
  `PuntoNovedad(palabra: "Hoy")` junto a la fase de hoy (el lint deja el magenta solo en `TLSDesign`). Un componente
  `MarcaHoy`/`LineaAhora` en `TLSDesign` serviría a las dos.
- **fichas → visores (hecho, 22/10):** la factura enseña su PDF con `VistaPreviaPDF(url:titulo:alto:alAbrir:)` («Abrir»
  entra en `.fichero`), y la vista previa flotante usa `MiniaturaFicheroVista` con los ficheros.
- **editor → todos (22/10): API del editor (PLAN §6.6).** Estable; se puede ampliar.
  - `TLSEditor`: `ControladorEditor(modo:escala:)` (un `NSTextView` de TextKit 2; `cargar(_:)`, `texto`,
    `sustituir(con:)` para lo que llega de fuera, `cambiarModo(_:)`, `alternarFuente()` ⌘E, `alternarLectura()` ⇧⌘E,
    `soloLectura`, `ponerCabecera(_:)`, `ir(a:)`, `desplazamiento`, `alternarCasilla(en:)`, `deshacer`; avisos
    `alCambiarTexto`, `alPerderFoco`, `alCambiarModo`, `alCambiarTitulos`, `alDesplazar`) y `EditorMarkdown(controlador:)`
    para enseñarlo. Protocolos: `AutocompletarEnlaces`, `ResolutorEnlaces` y `ProveedorIncrustaciones` (con
    `BloqueIncrustado`). Puro: `AnalizadorMarkdown.analizar(_:)`, `DisparoEnlace.detectar(en:cursor:)`.
    `EditorTextoMarkdown(texto:soloLectura:)` sigue igual (ahora es el editor de verdad) y admite además
    `modo:autocompletado:resolutor:incrustaciones:`.
  - `TLSUI/Editor`: `EditorTextoDeNota(texto:ruta:sesion:soloLectura:)` es ese editor con `[[`, ⌘clic e
    incrustaciones ya conectados a la sesión (para las Notas de una ficha, por sección; guarda quien lo usa).
    `NoteInspector(session:nota:)` sigue valiendo y amplía `titulos:irA:mostrarPropiedades:`; ahora trae
    `PropertiesForm` editable (una clave por cambio), «Menciones sin enlazar» con «Enlazar», «Índice» y «Abrir en
    Obsidian». `PropertiesForm(ruta:propiedades:sesion:motivoSoloLectura:compacta:)` se puede usar suelto.
  - Conflictos: `DiferenciasVersiones(titulo:mia:deFuera:alQuedarme:alUsarFuera:alCombinar:)` (comparación línea a
    línea y «Combinar a mano»).
- **editor → fichas (23/10):** `PropertiesForm.etiqueta(_:)` usa `InspectorFicha.etiqueta(_:)` para que una clave
  tenga el mismo nombre visible en la nota y en la ficha («codigo» → «Código»). Si cambia su firma, que siga
  existiendo una función con ese papel (o moverla a un sitio común, p. ej. `TLSUI/Support`).
- **editor (23/10): guardado en fila.** `ModeloNotaEditor.guardar()` encadena cada guardado al anterior (sin bucle
  de espera) y reintenta un choque `cambioExterno` como mucho 3 veces seguidas; `ControladorEditor.esperarPintado`
  tiene tope (`maximo:`, 10 s) y sale si se cancela (antes, con la tarea cancelada, `try? await Task.sleep` volvía al momento y daba vueltas al 100 % de CPU).
- **editor → cimientos (22/10, hecho en integración el 23/10: «Ver diferencias y combinar…» en las tarjetas de edición
  y de recuperación; `sesion.versionesParaCombinar(_:)` lee las dos versiones y se guarda con
  `.combinada(propiedadesDeFuera + cuerpo)`): «Combinar» en Revisar.** Basta con abrir `DiferenciasVersiones` desde la tarjeta de
  edición con los dos textos (`writer.conflicts.datos(de:root:)` de «Tu versión» y de «La de fuera») y llamar a
  `sesion.resolver(t, eleccion: .combinada(propiedadesDeFuera + cuerpo))`. El editor ya resuelve los suyos solo.
- **editor → cimientos/integración (22/10, hecho en integración el 23/10: `VaultService` mete en su `LinkResolver` las
  rutas de todos los ficheros con `IndexBuilder.rutasDeFicheros`, solo nombres, sin abrir ni descargar, sin ocultos ni
  lo excluido; `ResolutorAdjuntos` queda de respaldo para un adjunto recién llegado que aún no está en la caché):
  adjuntos en el resolvedor de enlaces.** El índice solo guarda `md`,
  `markdown`, `csv` y `txt`, así que `resolverEnlace("[[factura.pdf]]")` por nombre no encuentra un PDF de otra
  carpeta (con su ruta, sí). El editor lo suple con la lista de ficheros de `instantanea()` (`ResolutorAdjuntos`, leída
  en segundo plano y como mucho cada 10 s). Mejor: que `VaultService` meta en su `LinkResolver` las rutas de todos los
  ficheros (solo nombres, sin leerlos ni descargarlos). Con eso, `ResolutorAdjuntos` deja de hacer falta.
- **editor → escritor/integración (22/10, no se hace: decisión de integración del 23/10).** Crear `.obsidian/app.json`
  no hace que Obsidian conozca la carpeta: `obsidian://open?path=` solo abre bóvedas que Obsidian ya tiene en su lista.
  Se queda la explicación («ábrela antes desde Obsidian, Abrir carpeta») y `.obsidian/` sigue sin escribirse (la
  prueba del escritor lo vigila). Lo que se pedía: «Abrir en Obsidian» si falta `.obsidian/`. PLAN §6.6 pide ofrecer
  crearlo, pero `PlanCompiler.checkAllowed` rechaza todo componente oculto salvo seis rutas de `.tls/`. Cambio mínimo:
  admitir `.obsidian/app.json` (crear, nunca sobrescribir) solo a personas. Mientras, el inspector explica cómo
  abrir la carpeta desde Obsidian.
- **fichas → cimientos (22/10, resuelto en fichas el 23/10):** en `CabeceraAzulNoche` los datos clave comparten fila
  con las acciones y, con el destacado al lado, se recortaban. La ficha usa ahora su propia `CabeceraDeFicha`
  (`Fichas/CabeceraDeFicha.swift`, hecha solo con valores de `TLSDesign`) con la disposición de `M2-Contacto` y
  `M2-Proyecto`: identidad y acciones arriba (las acciones saltan debajo si a la identidad le quedan menos de 260 pt,
  `FilaConAcciones`), y la pastilla de estado y los datos en una fila propia a todo el ancho que salta de línea. Las
  acciones que no son la principal van con contorno blanco (`EstiloContornoCabecera`), como en las maquetas. Con eso
  el destacado vuelve a ir al lado desde 900 pt (§3.1). Si cimientos lleva esa disposición a `CabeceraAzulNoche`, la
  ficha puede volver a usarla sin cambiar nada más.
- **fichas (23/10): ampliaciones.** Estables; se pueden ampliar.
  - TLSCore: `MarkdownSections.titles(in:level:)` (solo las `##`, sin el `#` del título ni repetidas) y
    `TablaMarkdown.leer(_:)` (`cabecera`, `filas`, `\|` dentro de una celda, `sinNegrita(_:)` para la fila del total).
    El esquema añade `servicio` y `oferta_version` de la factura.
  - TLSUI: `TextoDeSeccion(texto:guia:)` pinta una sección con sus tablas como tablas (`VistaTablaMarkdown`), casillas,
    negritas y «Falta»; lo pueden usar otras pantallas. `AccionDocumento.de(modelo)` da las acciones de un documento
    según su estado (factura: Revisar y emitir —desactivada con su motivo hasta que la app emita—, Preparar el envío,
    Confirmar el cobro, Preparar recordatorio). «Confirmar el cobro» crea el recibo con su plantilla
    (`confirmado_por` = la persona) y pasa la factura a Cobrada en el mismo plan (un Deshacer): así se desbloquea
    Ganada en la oportunidad. `PreparadorNuevo(opcion:modelo:titulo:fecha:oportunidad:)` prepara y crea lo de
    «+ Nuevo» ya enlazado (`estado()`, `crear() async -> VaultPath?`, `enlaces(_:)` para «Nace enlazado con»).
    `AlmacenRelaciones.resolver` (el `LinkResolver` de la foto, hecho una vez por foto).
  - La pestaña Fichero suma «Adjuntos» (el PDF del documento y los ficheros que la nota enlaza o incrusta), «Abrir en
    Obsidian» (solo si la carpeta ya es de Obsidian; no crea nada) y una nota sobre versiones (sin historial propio
    hasta F2). Materiales es una galería con miniaturas (`MiniaturaFicheroVista`).
- **fichas → núcleo/F2 (23/10): versiones de una nota.** §3.2 pide en «Fichero» las versiones (SISTEMAS §5.8, 7 días
  y luego una al día hasta 30). El diario del escritor (`WriteJournal`) no es público y no guarda lo cambiado fuera de
  la app. Cuando exista un almacén de versiones, la pestaña Fichero las lista con «Mostrar cambios» y «Restaurar».
- **fichas → núcleo/F2 (23/10): emitir una factura.** «Revisar y emitir» sale desactivada con su motivo: no hay API
  de emisión (numerar con la serie, fecha, vence y PDF). Cuando la haya, `AccionDocumento` la llama sin más cambios.
