# TLS — Estado de la construcción

Fecha: 19/10/2026. Base: `multica-ai/multica@e752b971b`. Todo en local; no se ha subido nada al fork.

## Resumen

TLS funciona de punta a punta sobre la demo ficticia (Asesoría Ribera). Cubre las seis áreas, el viaje completo del cliente (interesado → propuesta → aceptación → factura → cobro → proyecto → cierre), finanzas con conciliación y paquete trimestral, y seis agentes trabajando a través de la API con aprobaciones, auditoría, interruptor global y sandbox. La app nativa se compila con Xcode.

Quedan pendientes las integraciones externas reales (correo, calendario, redes, banca por API), el portal del cliente, la instalación autónoma (servidor y PostgreSQL embebidos) y la distribución firmada.

## Fases

| Fase | Estado | Qué hay |
|---|---|---|
| 0 Auditoría y prueba Xcode/WebKit | ✅ | `FASE-0.md`; app en `apps/macos` |
| 1 Modelo, escritura segura, seis áreas, CRM, proyectos | ✅ | `server/internal/biz`, migraciones 585–591, carpeta portable con diario y reconstrucción |
| 2 Agentes, permisos, revisión, pausa, trazabilidad, presupuesto | ✅ con límites | Políticas por capacidad, aprobaciones, interruptor, pausa, auditoría, sandbox. El presupuesto se registra y se muestra; **no corta** ejecuciones al superarse |
| 3 Cadena comercial y de entrega, eventos durables, idempotencia | ✅ | Outbox `biz_event`, reintentos, `dead`; el proyecto se crea una sola vez |
| 4 Finanzas, importación bancaria, conciliación, paquete trimestral | ✅ | Importación CSV sin duplicados, conciliación propuesta y confirmada, paquete con trazabilidad |
| 5 Dirección, KPI, rituales, Marca, Equipo | ✅ | 21 KPI calculados, rituales diario, semanal, mensual y trimestral, madurez por evidencias |
| 6 Adaptadores reales, colaboración, distribución | ⏳ | Pendiente: correo, calendario, redes, banca API, Notion. Una sola persona en la demo. Build local firmada con «Apple Development», sin notarizar |

## Capacidades (78)

56 implementadas, 12 parciales, 2 simuladas (VEN-04 agenda, MAR-04 publicación en redes) y 8 pendientes (DIR-12, VEN-13, VEN-15, ENT-08 portal, ENT-12, ENT-13, FIN-11, EQU-11). Están visibles con su estado y su modo en cada área, pestaña **Sistemas**, y en `server/internal/biz/catalog.go`.

## Criterios de aceptación (§21)

| # | Criterio | Estado | Evidencia |
|---|---|---|---|
| 1 | Se abre desde Xcode y Finder sin servidor de desarrollo | ✅ | `apps/macos`, `xcodebuild` Release; el renderer se sirve desde el bundle (`tls-app://`) |
| 2 | Misma interfaz, temas y anchuras | ✅ | Componentes y tokens de Multica; capturas en claro y oscuro (web y app) |
| 3 | Onboarding vacío y demo sin `null` ni datos mezclados | ◐ | Demo completa y estados vacíos explicados. El onboarding guiado de empresa nueva es el de Multica: falta un asistente propio |
| 4 | Contacto y oportunidad: crear, editar, archivar, reabrir; validación por etapa en API | ✅ | `validateStage` + test `TestValidateStageRules` |
| 5 | Propuesta con versión de precio; cambiar la oferta no altera lo aceptado | ✅ | `TestPaymentConfirmationCreatesExactlyOneProject` |
| 6 | Aceptación → factura → cobro → un solo proyecto | ✅ | Mismo test (reentrega de todos los eventos: 1 proyecto) |
| 7 | Planificación y vencimiento independientes | ✅ | `issue.start_date` / `due_date` en días laborables |
| 8 | Agente: herramienta permitida sí, prohibida no; sin vía directa | ✅ | `TestAgentPolicyEnforcement`; sandbox (log del daemon `exec=/usr/bin/sandbox-exec`; denegaciones de la carpeta, credenciales, `.env` y PostgreSQL TCP/socket verificadas) |
| 9 | Equipo de agentes con dependencias, límites de gasto y concurrencia | ◐ | Comité con líder, concurrencia por agente (2) y por daemon. Profundidad y presupuesto se declaran pero **no se aplican** como corte automático |
| 10 | Cambiar contenido invalida la aprobación | ✅ | `TestApprovalInvalidatedWhenContentOrRecordChanges` |
| 11 | Reentregas y reinicios sin duplicar efectos | ✅ | Claves de idempotencia, `ON CONFLICT`, diario reanudado al arrancar |
| 12 | Pausa global detiene efectos nuevos | ✅ | Interruptor en la autorización, en la aprobación y en el *claim* (`ClaimGate`) |
| 13 | Reimportar extracto sin duplicar | ✅ | `TestBankImportIsIdempotent…`; demo: 29 duplicados ignorados |
| 14 | Desconocido no es cero | ✅ | Caja desconocida sin saldo; estados `no_data`, `partial` y `not_configured` |
| 15 | Paquete trimestral correcto, sin presentar sin evidencia | ✅ | `TestPeriodRequiresEvidenceAndKeepsHistory`; `Finanzas/2026/T3/Paquete gestoría` |
| 16 | Fechas sin hora conservan el día (Europe/Madrid) | ◐ | DATE en servidor, formateo sin conversión en cliente. Faltan tests específicos de cambio de horario |
| 17 | Borrar el índice y reconstruir conserva los datos campo a campo | ✅ | `TestFolderRebuildRestoresProjectionFieldByField` |
| 18 | Edición externa incompatible y conflicto de ID visibles | ✅ | Mismo test (edición detectada, ID duplicado reportado) |
| 19 | Aislamiento entre empresas por URL, API, búsqueda y agentes | ✅ | Toda consulta filtra `workspace_id`; el token de tarea fija el workspace en el servidor |
| 20 | Sin modelo ni red, la gestión manual funciona | ✅ | Todas las acciones están disponibles para personas sin agentes |
| 21 | Cerrar y reabrir sin procesos huérfanos | ✅ | Verificado en la Fase 0; el daemon se para al salir si se configura |
| 22 | Copia y restauración probadas | ◐ | Reconstrucción desde la carpeta probada; falta la copia completa del runtime (PostgreSQL) automatizada |
| 23 | Teclado, foco y contraste; estado no solo por color | ◐ | Estados con icono y texto, filas navegables con teclado. Sin auditoría formal de accesibilidad |
| 24 | Rendimiento con 10.000 contactos / 50.000 tareas | ❌ | No medido |

## Pruebas ejecutadas

| Suite | Resultado |
|---|---|
| `go test ./internal/biz` (unitarias + integración con PostgreSQL) | ✅ 13 tests, 3 ejecuciones seguidas |
| `go test ./pkg/agent` | ✅ |
| `go test ./internal/handler` | ✅ tras registrar las tablas `biz_*` en el borrado de workspaces |
| `vitest` core | 2.258 de 2.269. Los 11 fallos **ya existen en upstream** con este entorno (mutaciones y realtime); verificado en una copia limpia del commit base |
| `vitest` views | ✅ 6.202 de 6.202 |
| Typecheck core, views, web y desktop | ✅ |
| Recorrido real con agentes (Claude) | ✅ Comercial (cualificación + mensaje en aprobación), Financiero (revisión del paquete), Dirección (foco del día y plan semanal), Equipo (prueba de seguridad: se niega a saltarse los controles) |

## Limitaciones conocidas

- **Instalación:** la app necesita el servidor Go y PostgreSQL locales (`scripts/tls/start-demo.sh`). No es autónoma.
- **Credenciales:** el token de sesión sigue en el almacenamiento web (como en Multica); el del daemon, en `~/.multica` con permisos 0600. No usan el Llavero.
- **Presupuesto y profundidad de delegación:** se registran y se muestran, pero no detienen una ejecución.
- **Integraciones:** no se envía correo ni se publica; se registra como pendiente manual.
- **Coste de agentes:** Claude no informa coste en esta versión; se muestran tokens y «no informado».
- **Recurrencia:** cada trimestre de un cliente es una oportunidad nueva; falta la renovación automática de servicios recurrentes.
- **Idioma:** el módulo Empresa está en español sin traducciones; el resto de la app tiene español completo.
