# The Last System

App nativa de Mac (SwiftUI + AppKit) que abre la carpeta de tu empresa como Obsidian y la hace funcionar con
asistentes. **Los archivos mandan**: la carpeta en Markdown es la
verdad y SQLite es solo un índice desechable. El plan completo está en [`docs/PLAN.md`](docs/PLAN.md).

Versión **1.0.0** («v1»): F0 a F6 terminadas. La carpeta de tu empresa en Markdown, con Hoy, Decisiones, Tareas, las
seis áreas, el banco por extractos, la puesta en marcha, el tutorial, el manual, los asistentes y las conexiones.

**Qué hace la v1**
- **Abre la carpeta de tu empresa como Obsidian** (F0–F1): editor en vivo, enlaces que se mantienen al renombrar,
  visores de PDF, imagen, audio y vídeo, «Mostrar en Finder». Escribe siempre por `CommandBus`: todo se deshace y nada
  se borra (lo retirado va a `Archivo/`). Lo privado no se copia ni lo ve ningún asistente.
- **Tareas y áreas** (F2): Hoy con un solo foco, Decisiones (1-3-1), Tareas, las 6 áreas con sus números clave, el
  banco por extracto con conciliación (confirmar un cobro es siempre tu clic) y las reglas del dominio (Ganada solo con
  cobro confirmado, proyecto y tareas de la plantilla).
- **Puesta en marcha** (F3): una copia de tu carpeta (la real no se toca), ordenar lo que tienes, el tutorial y el
  manual, e importar tus tareas de Multica.
- **Asistentes** (F4): uno por área más Mika, que trabajan con **tu Claude Code** en una caja cerrada y solo a través de
  la app (`tls-mcp`); preparan, proponen y preguntan, y **nada sale sin tu OK**. En el ejemplo, todo simulado.
- **Conexiones** (F5): **Mail** con el Cartero (solo lee la cuenta que elijas; lo privado queda en «correo privado de
  …»; al aprobar un correo se abre la redacción en Mail y **enviar es tuyo**), **Calendario** (un calendario propio
  «The Last System» con tus rituales y sesiones, sin invitar a nadie; de los demás, solo «Ocupado») y **otros
  programas** (web y formularios, GoHighLevel, Stripe, Calendly u otro compatible): claves en el Llavero, interruptores
  en llano por asistente, lo sensible siempre con tu OK atado a lo aprobado, herramientas nuevas apagadas hasta que las
  revises y lo que llega, reflejado en tus fichas una sola vez; los nombres de lo que hacen allí, en llano («Mandar un
  SMS desde GoHighLevel»). Antes de cada permiso del Mac, una explicación; si lo
  deniegas, cómo arreglarlo. En el ejemplo, Mail y Calendario no se conectan y el programa es simulado.
- **Relevo a la carpeta real** (F6): «Pasar a mi carpeta real» (Ajustes › Esta empresa), **solo cuando tú lo
  decidas**: comprueba que la otra aplicación no la usa, enseña la vista previa, pide escribir el nombre de la empresa,
  guarda copia de seguridad, aplica exactamente la vista previa y se deshace (también después, desde Ajustes ›
  «Deshacer el último relevo»). Lo que marcaste privado en la copia sigue privado en la real, y un cambio hecho en la
  real después de la copia nunca se pisa sin preguntarte (se compara el contenido, no la fecha). Después, la app
  escribe en tu carpeta real.

**Qué no hace la v1** (PLAN §12): enviar correos, invitar a eventos, publicar, facturar ni pagar por su cuenta (siempre
tú); varias personas o varios Macs escribiendo a la vez; banco por API, webhooks o leer Mail por ficheros; app firmada
para terceros (sin notarizar, sin actualizaciones automáticas, solo Apple Silicon).

- Contratos: [`docs/F0-CONTRATOS.md`](docs/F0-CONTRATOS.md), [`docs/F1-CONTRATOS.md`](docs/F1-CONTRATOS.md) (núcleo),
  [`docs/F1-INTERFAZ-CONTRATOS.md`](docs/F1-INTERFAZ-CONTRATOS.md) (interfaz), [`docs/F2-CONTRATOS.md`](docs/F2-CONTRATOS.md)
  (números, dominio, banco, pantallas e integración de F2), [`docs/F3-CONTRATOS.md`](docs/F3-CONTRATOS.md) (puesta en
  marcha, ordenar, tutorial, manual, Multica, integración y los 10 criterios de F3 con su prueba) y
  [`docs/F4-CONTRATOS.md`](docs/F4-CONTRATOS.md) (gobierno, motor, `tls-mcp`, roles, pantallas, Mika, integración y los
  10 criterios de F4 con su prueba) y [`docs/F5-CONTRATOS.md`](docs/F5-CONTRATOS.md) (Mail, Calendario, otros
  programas, relevo, pantallas, integración y los criterios de F5 y F6 con su prueba).
- Diseño aprobado: [`docs/propuesta/DISENO-MOSAICO-V2.md`](docs/propuesta/DISENO-MOSAICO-V2.md).
- Pruebas manuales: [`docs/pruebas/F0.md`](docs/pruebas/F0.md), [`docs/pruebas/F1.md`](docs/pruebas/F1.md),
  [`docs/pruebas/F2.md`](docs/pruebas/F2.md) (10–15 min con el ejemplo de Asesoría Ribera) y
  [`docs/pruebas/F3.md`](docs/pruebas/F3.md) (el ejemplo y el tutorial, la puesta en marcha sobre una copia nueva de tu
  carpeta, tus tareas de Multica y actualizar la copia), [`docs/pruebas/F4.md`](docs/pruebas/F4.md) (Mika y un
  borrador simulado en Ribera; en tu copia, una tarea para el Contable con tu Claude Code, pausar y salir),
  [`docs/pruebas/F5.md`](docs/pruebas/F5.md) (Mail y el Buzón, un borrador que se abre en Mail sin enviarse, el
  Calendario y su ritual, añadir un programa) y [`docs/pruebas/F6.md`](docs/pruebas/F6.md) (el relevo, **solo cuando
  tú lo decidas**).

## Instalación

1. Comprueba el disco: `cd dist && shasum -a 256 -c SHA256SUMS-1.0.0.txt` (debe decir `OK`).
2. Abre `dist/The-Last-System-1.0.0.dmg`, arrastra **The Last System** a **Aplicaciones** (si ya la tenías, «Reemplazar»:
   tus empresas, ajustes y permisos se conservan) y expulsa el disco.
3. Ábrela: el selector ofrece **Ver un ejemplo** (Asesoría Ribera, ficticia), **crear una copia de tu carpeta** (la
   recomendada: tu carpeta real no se toca) o **Ver sin tocar**. La puesta en marcha te guía después.
4. Opcional: Claude Code con tu sesión iniciada para los asistentes (manual › «Conectar Claude Code») y Ajustes ›
   Conexiones para Mail, Calendario y otros programas.

## Requisitos

- Mac con Apple Silicon y macOS 15 o posterior (la v1 es solo arm64).
- Xcode 26.6 (Swift 6.3, modo estricto de Swift 6).
- Opcional: [Homebrew](https://brew.sh) para instalar `xcodegen`. El `.xcodeproj` va versionado y compila sin él.

## Empezar

```sh
make bootstrap   # comprueba Xcode y xcodegen (lo instala con brew si falta) y resuelve dependencias
make firma       # firma con tu equipo de Apple (ver «Firma»)
make test        # swift test del paquete TLSKit + compilación de la app
make capturas    # PNG fuera de pantalla de F1 a F6 (claro y oscuro) → build/capturas/index.html, f3.html, f4.html y f5.html
make dmg         # Release arm64 → dist/The-Last-System-<versión>.dmg y dist/SHA256SUMS-<versión>.txt
make verify      # firma de la app y de tls-mcp, permisos, hdiutil verify, sumas, contenido del DMG y sandbox real
```

Otros objetivos: `make gen` (regenera el `.xcodeproj` desde `project.yml`), `make build` (Debug),
`make release` (Release sin DMG), `make conformidad`, `make sandbox` (asistentes con Claude Code real),
`make tls-tool`, `make clean`. `make` a secas
muestra la ayuda. Las rutas se cambian con variables: `make dmg DERIVED=build/otro DIST=salida`.

**Después de añadir ficheros a `App/` o `Helpers/`, o de tocar `project.yml`, ejecuta `make gen`** y
versiona el `.xcodeproj` resultante. Los ficheros nuevos del paquete `Packages/TLSKit` no lo necesitan.

`tls-tool` (desarrollo): `copiar`, `inventario`, `indexar`, `convertir-g2`, `renombrar <carpeta> <ruta> <nombre>
[--aplicar]` (vista previa y renombrado con todos los enlaces) y `deshacer <carpeta>`. Las dos últimas solo escriben en
copias y en la demo.

Varios agentes compilando a la vez: cada uno usa su propio directorio de SwiftPM,
`swift build --package-path Packages/TLSKit --scratch-path build/spm-<rol>` (y `swift test` igual).

## Firma

- **Por defecto, ad hoc** (`Config/Base.xcconfig`): compila sin cuenta, pero macOS vuelve a pedir
  los permisos tras cada build y `make dmg` avisa.
- **Con tu equipo personal** (gratuito): `make firma` ejecuta `scripts/configurar-firma.sh`, que busca
  un certificado «Apple Development» con `security find-identity`, saca el Team ID del OU del
  certificado y escribe `Config/Signing.local.xcconfig` (no se versiona; `Base.xcconfig` lo incluye):

  ```
  CODE_SIGN_STYLE = Automatic
  CODE_SIGN_IDENTITY = Apple Development
  DEVELOPMENT_TEAM = <Team ID>
  ```

  Con equipo, `xcodebuild` se lanza con `-allowProvisioningUpdates`.
- **Si no hay certificado:** Xcode › Ajustes › Cuentas → tu Apple ID → «Manage Certificates…» →
  «+» → «Apple Development», y otra vez `make firma`. Si ya conoces el Team ID:
  `scripts/configurar-firma.sh --equipo <ID>`. Para volver a ad hoc: `scripts/configurar-firma.sh --ad-hoc`.
- Criterio de F0: `codesign -dv` muestra `Authority=Apple Development: …` en la app y en
  `Contents/Helpers/tls-mcp`. Con `TLS_EXIGIR_FIRMA=1`, `make dmg` y `make verify` fallan si la firma es ad hoc.
- **Estado (23/10/2026):** firma con el equipo personal `<TEAM_ID>` (certificado «Apple Development»). Sirve para
  este Mac y para los Mac registrados en el equipo; macOS conserva los permisos entre versiones. Para dar la app a
  otras personas sin el aviso de Gatekeeper hace falta el programa de desarrolladores de pago: un certificado
  «Developer ID Application» y notarizar el DMG (`xcrun notarytool`). Queda para cuando se venda.
- Si `xcodebuild` avisa `DVTDeveloperAccountManager: … missing Xcode-Username`, la sesión del Apple ID en Xcode está
  caducada: compila y firma igual con el certificado del llavero, pero no podrá renovar certificados ni perfiles.
  Se arregla en Xcode › Ajustes › Cuentas (quitar y volver a añadir el Apple ID); lo hace la persona, con su contraseña.

## Dónde vive el estado

Nada técnico se guarda dentro de la carpeta de la empresa (PLAN §3.4):

| Ruta | Contenido |
|---|---|
| `~/Library/Application Support/The Last System/` | `vaults.json` (carpetas conocidas, exclusiones de copia), `instalacion.json`, `tutorial.json` (el avance del tutorial) y `tutorial/` (el extracto de ejemplo) |
| `…/The Last System/<id>/index.sqlite` | Índice y búsqueda. **Desechable**: se reconstruye al abrir |
| `…/The Last System/<id>/` (resto) | Estado que no se borra: `estado.sqlite` (desde la 0.3, la bandeja de eventos del dominio y lo que ya hizo cada regla), `diario.jsonl`, copias previas (de lo que cambia; lo que solo se mueve no la necesita), `hoy.json` e `inicios.json` (lo que decides en Hoy y cómo ordenas tus módulos), `miniaturas/` (caché de las miniaturas de PDF); desde la 0.4, `onboarding.json` (la puesta en marcha, tras cada respuesta), `ordenar/borrador.json` (lo decidido en «Ordenar lo que tienes»; lo privado, solo por su huella) e `importaciones/` (el mapa de cada importación, `origen,destino,accion,motivo,conflicto`) |
| `…/The Last System/<id>/` (F4, 0.5) | En `estado.sqlite`, también lo de los asistentes: cola de trabajos, disparos ya vistos, uso del mes, aprobaciones, propuestas, la configuración confirmada y la auditoría de cada decisión. `agentes/<slug>/` (la carpeta de trabajo de cada asistente, la misma siempre: Claude apunta un solo proyecto por asistente) y `ejecuciones/<trabajo>/` (perfil de la caja, `mcp.json` y token con permisos 0600, registro del trabajo; se borran a los 90 días) |
| `…/The Last System/<id>/` (F5, 1.0) | `correo/AAAA-MM-DD.jsonl` (el correo que leyó la app, 0600; lo privado, solo «correo privado de …») y `correo/ajustes.json` (la cuenta y los remitentes privados); en `estado.sqlite`, `cursor_correo` y `mapa_calendario`; `conexiones.json` (otros programas, **sin claves**: solo el nombre del campo) y `conexiones/<id>/` (directorio de trabajo de un programa de este Mac) |
| `…/The Last System/<id de la real>/` (F6) | `relevo.json` (la marca del relevo: hecho o deshecho) y `relevo/<fecha>/` (copia de seguridad de lo que se tocó, con `indice.json`, `inventario-antes.json`, `escritor.json.anterior` y `vaults.json.anterior`) |
| `…/The Last System/s/<id8>.sock` | El socket de `tls-mcp` de cada empresa abierta (0600, carpeta 0700); se borra al cerrarla o al salir |
| `~/The Last System/Empresas/` | Las carpetas visibles en Finder: `The Last (copia AAAA-MM-DD)/` y `Asesoría Ribera (ejemplo)/` |
| `~/Library/Logs/The Last System/` | Registros |
| Llavero | Secretos (nunca en ficheros ni variables de entorno): las claves de otros programas, servicio `es.thelast.system.gateway`, cuenta `<id>.<campo>` |

Dentro de la carpeta de la empresa solo va lo que es de la empresa y debe viajar con ella: `.tls/` (configuración,
`escritor.json` del escritor de F1 y, desde la 0.2, las vistas guardadas de cada base en `.tls/vistas/<base>.json`,
escritas por `CommandBus`). Lo que se retira o se deshace va a `Archivo/`; nunca se borra.

En pruebas se pueden redirigir con `TLS_APP_SUPPORT` y `TLS_EMPRESAS`.

## Estructura

```
project.yml            XcodeGen → TheLastSystem.xcodeproj (versionado)
Config/                Base.xcconfig (versión, firma ad hoc) · Signing.local.xcconfig (local, no versionado)
App/                   target «The Last System»: Info.plist, permisos, Sources/, Recursos/ (Ribera y el manual)
Helpers/tls-mcp/       auxiliar embebido en Contents/Helpers: el servidor de herramientas de los asistentes (stdio ↔ socket de la app)
Packages/TLSKit/       paquete SPM: TLSCore (con el motor de la puesta en marcha), TLSImport (ordenar, OCR, fechas, Multica),
                       TLSAgents, TLSDesign (Mosaico v2, letras, anclas del tutorial), TLSEditor, TLSVisores (PDF,
                       imagen, audio, vídeo), TLSUI (con el tutorial y el manual), TLSOnboarding (la ventana de la puesta
                       en marcha), TLSMCPShared y TLSMCPHost (`tls-mcp`: protocolo, socket, herramientas), TLSIntegracion
                       (lo de cada empresa abierta: motor, servidor, chat y conexiones), TLSIntegrations (Mail, Calendario
                       y permisos del Mac, detrás de protocolos), TLSGateway (otros programas: pasarela, Llavero, catálogo
                       con huella, plantillas), tls-tool y tests
scripts/               build-dmg.sh · configurar-firma.sh · verificar.sh · conformidad.sh · verificar-sandbox.sh · capturas.sh
docs/                  PLAN.md · F0/F1/F2/F3/F4/F5-CONTRATOS.md · F1-INTERFAZ-CONTRATOS.md · PROCEDENCIA.md · pruebas/F<n>.md
```

## Reglas del repositorio

- **Los datos reales nunca entran aquí.** Tests con fixtures sintéticas; el ejemplo es la empresa
  ficticia «Asesoría Ribera». `docs/privado/` y `Config/Signing.local.xcconfig` están en `.gitignore`.
- **Sala limpia**: qué se porta de dónde y con qué autoría está en [`docs/PROCEDENCIA.md`](docs/PROCEDENCIA.md).
- Comentarios breves en español; tipos técnicos en inglés y conceptos de negocio en español. Tests con
  Swift Testing. Los textos visibles siguen el glosario del PLAN §6.9 («carpeta de tu empresa»,
  «propiedades», «asistente»…).
