# TLS — Fase 0: auditoría de upstream y prueba Xcode/WebKit

Fecha: 19/10/2026. Estado: **cerrada con condiciones pendientes** (ver §6).

## 1. Base

| Dato | Valor |
|---|---|
| Upstream | `multica-ai/multica`, rama `main` |
| Commit base | `e752b971b8c661ad7b2dfe1a049442d7c40f359a` (coincide con la referencia del prompt maestro) |
| Fork | `LeonMAG/multica` (`origin`); upstream como remoto `upstream` |
| Extensiones TLS | `apps/macos/` (host nativo) y `docs/tls/`. El resto del árbol está sin modificar salvo `apps/desktop/package.json` y `apps/desktop/scripts/package-mac-local.sh` (build Electron local firmada) |

Entorno de desarrollo verificado en este Mac (Apple Silicon, macOS 26.3, Xcode 26.6): Node 26.7, pnpm 10.28.2 (corepack), Go 1.27.2, PostgreSQL 17.11 (Homebrew), XcodeGen 2.46. No hay Docker: la base de datos local se creó a mano (`createdb multica`) porque `scripts/ensure-postgres.sh` asume Docker para hosts locales.

## 2. Licencia

Se ha leído `LICENSE` del commit base. Es Apache 2.0 con condiciones adicionales del productor (Index Labs):

- **Uso interno** en una sola organización: permitido sin licencia comercial.
- **Publicar el código del fork** en un repositorio público: permitido; no es un servicio alojado.
- **Alojar para terceros** (SaaS, instancia pública, aunque sea gratis) o **incorporarlo a un producto vendido o distribuido comercialmente**: requiere **licencia comercial**.
- **Marca**: no se puede quitar ni modificar el logo de Multica, el nombre «Multica» ni los avisos de copyright mostrados en una interfaz derivada (incluye `apps/desktop`, `packages/views`, `packages/ui` y cualquier app compilada a partir de ellos) sin **dispensa escrita**.
- Conservar `NOTICE`.

Consecuencias aplicadas en esta fase:

- La interfaz conserva intactos el logo, el nombre y los avisos de Multica (la pantalla de login sigue diciendo «Sign in to Multica»).
- El host se llama «TLS» como nombre interno provisional. El bundle incluye `LICENSE` y `NOTICE`, el copyright del `Info.plist` dice «Built on Multica» y el menú Ayuda enlaza a la licencia y al repositorio.
- **Pendiente de decisión del titular:** si TLS se va a vender o distribuir a terceros, hace falta la licencia comercial; si se quiere otra marca en la interfaz, además la dispensa de marca. Son concesiones distintas. Sin ellas, la distribución queda limitada a uso interno.

## 3. Mapa de reutilización

Resumen de tres auditorías del código (frontend, Electron y backend). **R** = se reutiliza tal cual; **A** = se amplía; **F** = falta y hay que construirlo.

| Requisito TLS (sección del prompt) | Estado | Pieza de Multica |
|---|---|---|
| Workspace por empresa (§7) | R | `workspace` (con `settings` JSONB) |
| Autenticación (§4) | R | Código por email, Google OAuth, JWT; PAT `mul_`; tokens de tarea `mat_` por ejecución |
| Roles de la aplicación (§14) | A | Solo `owner/admin/member`; falta matriz por capacidad |
| Shell, navegación, temas, tokens (§5) | R | `packages/views/layout/app-sidebar.tsx`, `packages/ui/styles/tokens.css`, pestañas de escritorio |
| Grupo «Empresa» en la barra lateral (§5) | A | Arrays estáticos de navegación + registros en `packages/core/paths` (rutas, iconos, pestañas, slugs reservados) |
| Colores de área (§5) | A | Añadir `--area-*` en `:root` y `.dark` y mapearlos en `@theme inline` |
| Tablas, kanban, cronograma, inspector (§5) | R/A | `data-table`, `ListGrid`, `board-view`, `gantt-view`, `AnimatedRightSidebar`; kanban y gantt están acoplados a Issue y se copian como patrón |
| Español en la interfaz | F | Locales: en, zh-Hans, ko, ja, fr. Añadir `es` toca core, server y todos los namespaces |
| Tareas únicas con planificación y vencimiento (§7, §11) | R | `issue.start_date` / `issue.due_date` (DATE) |
| Campos empresariales en tareas | R | `issue_property` + `issue.properties` (campos personalizados tipados) |
| Dependencias entre tareas (§11) | A | Tabla `issue_dependency` existe pero **ningún código la usa** |
| Proyectos con objetivo (§7, DIR-03) | A | `project` sin objetivos, hitos ni propiedades |
| CRM: organizaciones, contactos, oportunidades, ofertas versionadas (§10) | F | — |
| Finanzas, conciliación, trimestre (§12) | F | — |
| Marca, contenidos (§13) | F | — |
| Áreas, roles de negocio, KPI, rutinas (§7, §18) | F | Rutinas: se reutilizan `autopilot` (cron) e `issue_wakeup` |
| Agentes por área (§15) | A | `agent` + `area_id` |
| Coordinador y equipos de agentes (§15) | R/A | `squad` con agente líder; falta límite de profundidad de delegación |
| Concurrencia (§15) | R | `agent.max_concurrent_tasks`, límite por daemon |
| Presupuesto y gasto (§15, EQU-13) | A | Coste registrado (`task_usage`, `task_usage_hourly`); **no hay topes de gasto** |
| Aprobaciones de cambios de agentes (§16) | F | Solo estado `in_review` y comentarios |
| Interruptor global, pausa por área, modo lectura (§16, DIR-11) | F | Punto de enganche: ruta de *claim* de tareas y `CancelTasksForAgent` |
| Auditoría general (§16) | A | `activity_log` solo cubre issues y se escribe *best-effort* fuera de la transacción |
| Eventos durables, outbox, idempotencia (§17) | A | Patrones existentes: `seat_capacity_outbox`, `webhook_delivery`, `sys_cron_executions`; el bus de eventos es en memoria |
| Carpeta portable y reconstrucción (§8) | F | — |
| Proveedores de agentes (§15) | R | ~25 adaptadores de CLI; verificado en esta build: **Claude** |
| Panel de agente con contexto (§5) | A | `FloatingChat`; el contexto solo reconoce issues y proyectos |

## 4. Prueba técnica Xcode/WebKit

### Arquitectura

```
TLS.app (Swift/AppKit, target Xcode)
├─ WKWebView ── tls-app://app/  ← AppSchemeHandler sirve Resources/renderer (build de apps/desktop)
│   └─ bridge.js recrea window.desktopAPI / daemonAPI / updater sobre webkit.messageHandlers.tls
├─ NativeBridge  ← acciones cerradas; solo marco principal del origen tls-app://app
├─ DaemonManager ← lanza Resources/bin/multica (daemon) con perfil propio "tls-local"
└─ RuntimeConfig ← ~/Library/Application Support/TLS/runtime-config.json (servidor explícito)
```

El renderer de escritorio se ejecuta **sin cambios**: el puente reproduce la forma de `apps/desktop/src/preload/index.d.ts`. No hay servidor de desarrollo ni `file://`.

### Resultados verificados

| Criterio de cierre de la Fase 0 | Resultado | Evidencia |
|---|---|---|
| Ventana con navegación heredada | ✅ | Barra lateral, pestañas y tablero de issues de Multica dentro de WKWebView (`img/fase0-xcode-wkwebview.png` frente a `img/fase0-web-original.png`) |
| Inicio de sesión | ✅ | Login por código desde el origen `tls-app://app`; CORS y WebSocket aceptados con `CORS_ALLOWED_ORIGINS` (sin tocar el servidor) |
| Sesión persistente | ✅ | Tras cerrar y reabrir la app la sesión sigue activa (`WKWebsiteDataStore.default()`) |
| Lectura y escritura persistente | ✅ | Agente e issue creados por la API desde la app y leídos en PostgreSQL |
| Ejecución de agente | ✅ | El host arrancó el daemon embebido (PAT acuñado, 5 runtimes detectados). Un agente con runtime Claude completó DEMO-2 y comentó «Prueba TLS OK»; tokens registrados en `task_usage` |
| Selector de carpeta | ⚠️ Implementado, sin verificar | `NSOpenPanel` como hoja + validación de carpeta y repo git. Requiere un clic humano; no se pudo automatizar |
| Build reproducible con `xcodebuild` | ✅ | `apps/macos/scripts/build.sh` → Release firmada con «Apple Development», hardened runtime en la app y en el binario `multica` |
| Apertura desde Finder | ✅ | Lanzada con `open` (mismo mecanismo que Finder), sin Node, Go ni pnpm en tiempo de ejecución |

### Lo que el host aún no hace

- **Servidor y base de datos embebidos.** La app se conecta a un servidor configurado (`localhost:8080`). Para instalación autónoma hay que empaquetar `server` y resolver PostgreSQL local (distribución, actualización y copias). Hasta entonces, **no se afirma instalación autónoma**.
- **Credenciales en Keychain.** El token de sesión sigue en `localStorage` (como en Electron) y el PAT del daemon en `~/.multica/profiles/tls-local/config.json` (permisos 0600). Requisito §4 pendiente.
- **Arrastre de ventana.** WebKit ignora `-webkit-app-region`; se emula con la franja superior de 48 px (salvo controles interactivos). Falta revisarlo a mano en todas las pantallas.
- **Actualizaciones** (Sparkle), **descargas con diálogo de guardado** (ahora abren el navegador), **recuperación de caídas del daemon** y **descarga del CLI** cuando no está embebido.
- **Intel.** Solo arm64 compilado y probado.
- **macOS mínimo.** Declarado 13.0 por las APIs usadas (`WKScriptMessageHandlerWithReply`, `WKUIDelegate` de descargas). Solo probado en macOS 26.3.
- **Notarización.** No hay certificado *Developer ID*; la build es local. No está notarizada.

## 5. Hallazgo de seguridad (bloqueo antes de datos reales)

Los agentes heredados se ejecutan **con acceso completo a shell y sistema de ficheros**: Claude con `--permission-mode bypassPermissions` (`server/pkg/agent/claude.go`) y Codex con `danger-full-access` (`server/internal/daemon/execenv/codex_sandbox.go`). El aislamiento es solo un directorio de trabajo por tarea, sin sandbox del sistema.

El §16 del prompt exige que un agente no pueda saltarse el control escribiendo directamente en la carpeta de la empresa. **Con este runtime no se cumple.** Antes de conectar datos reales hay que confinar el runtime (sandbox de macOS o contenedor por tarea, sin acceso a la carpeta de empresa) y canalizar las mutaciones por herramientas autorizadas. La prueba de esta fase usó un workspace ficticio y una tarea inocua.

## 6. Decisiones pendientes del titular

1. **Licencia comercial y dispensa de marca** si TLS se va a distribuir o vender (§2).
2. **Confinamiento de agentes** (§5): aceptar el coste de diseñarlo en la Fase 2 antes de cualquier dato real.
3. **PostgreSQL embebido o servidor remoto** para la versión instalable.
4. **Certificado Developer ID** (cuenta Apple Developer de pago) para notarizar y distribuir fuera de este Mac.

## 7. Cómo arrancar

```bash
# Backend local (requiere PostgreSQL 17 en marcha)
cd server && set -a && . ../.env && set +a && go run ./cmd/migrate up && go run ./cmd/server

# App macOS (Release firmada)
apps/macos/scripts/build.sh
open apps/macos/build/DerivedData/Build/Products/Release/TLS.app

# O desde Xcode: apps/macos/scripts/prepare-artifacts.sh y abrir apps/macos/TLS.xcodeproj (scheme TLS)
```

`.env` local: `APP_ENV=development`, `MULTICA_DEV_VERIFICATION_CODE=888888` (solo local), `CORS_ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173,tls-app://app`.

## 8. Siguiente fase

Fase 1: modelo empresarial y escritura segura. Áreas, empresa/demo separadas, contactos, organizaciones, ofertas, oportunidades, proyectos con objetivo y tareas, con CRUD real, aislamiento por workspace, carpeta portable con diario de recuperación y reconstrucción, y el grupo «Empresa» en la navegación. Incluye añadir el idioma español.
