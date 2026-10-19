# TLS — Decisiones de diseño

Decisiones tomadas al construir TLS sobre Multica, con su motivo. Las que dependen del titular están al final.

## Producto

| Decisión | Motivo |
|---|---|
| Tareas y proyectos son los de Multica (`issue`, `project`) | El prompt pide no duplicar entidades. Una tarea que ve Ventas y luego Dirección es la misma fila. |
| Cada servicio tiene su **canvas** = un flujo de trabajo de Multica (`issue_workflow`) con estados propios | Renta y Trimestrales son ciclos productivos distintos; el tablero del proyecto muestra sus columnas. |
| Las tablas nuevas llevan prefijo `biz_` y viven en `server/internal/biz` | Delimitan la extensión para poder seguir trayendo cambios de upstream. |
| Workspace = empresa. Demo y producción son workspaces distintos con carpeta propia | Aislamiento de datos, colas y credenciales por empresa (§8, §19). |
| Ganada = cobro confirmado. Aceptada = compromiso comercial pendiente de cobro | Política TLB: el proyecto arranca con el cobro (§10, §17). La factura se emite tras la aceptación, antes del cobro, sin ciclo. |
| Precio vigente único por servicio (`biz_offer_version`); propuesta y factura guardan instantánea | Cambiar el catálogo no altera contratos ni facturas (§10). |
| Dinero en céntimos enteros (`*_minor`), redondeo half-up explícito | Nunca flotantes para importes (§12). |
| Desconocido ≠ cero: KPI con estados `no_data`, `not_configured`, `partial`, `disabled` | §5, §18, §21.14. |
| Madurez por evidencias (procesos escritos, responsable, delegación explícita), no por número de agentes | §18. |
| Decisiones solo añadibles (`superseded` + `supersedes_id`) | §9: las correcciones no borran lo decidido. |

## Ejecución y seguridad

| Decisión | Motivo |
|---|---|
| Toda escritura de negocio pasa por `Service.Run` (acción registrada) | Mismo control para UI, agentes y aprobaciones: política, auditoría, eventos y carpeta. |
| Modos por capacidad: desactivada, manual, asistido, supervisado, autónomo con límites | §16. Por defecto: sensibles → supervisado (aprobación); el resto → asistido. |
| Acciones sensibles de agentes crean una **aprobación** ligada al hash del contenido y a la versión del registro | Cambiar contenido, destinatario o importe, o el registro, invalida la aprobación (§16, §21.10). |
| Interruptor global: bloquea escrituras de agentes/automatismos, cancela la cola y veta el *claim* de tareas | DIR-11. Comprobado al pedir, al aprobar y al reclamar ejecución. |
| Agentes confinados con sandbox de macOS (`MULTICA_AGENT_SANDBOX_PROFILE`) | §16: sin lectura/escritura de la carpeta de empresa, credenciales del daemon, `.env` ni acceso directo a PostgreSQL. Solo la API. |
| Eventos de negocio en outbox transaccional (`biz_event`) con clave de idempotencia, reintentos con espera creciente y estado `dead` | Entrega al menos una vez y efectos idempotentes (§17). |
| Modo importación (`import_mode`) | Cargar histórico no dispara agentes ni efectos de negocio (§19). |
| Rituales generados una vez por periodo aunque el Mac estuviera apagado; no se rellenan días pasados | §17: recuperar lo pendiente según política. |

## Datos portables

| Decisión | Motivo |
|---|---|
| Carpeta = representación durable legible (Markdown + frontmatter YAML); PostgreSQL = proyección | §8. |
| Diario `biz_journal`: intención en la misma transacción → escritura atómica (temporal + rename) → commit con hash | No se pierde un cambio confirmado; se reintenta al arrancar. |
| Identidad = campo `id`; el nombre del fichero lleva un id corto | Renombrar no cambia la identidad. |
| Reconstrucción con vista previa, comparación campo a campo y conservación de campos desconocidos en `attrs` | §8, §21.17. |
| Ediciones externas detectadas por hash, no por `mtime`; IDs duplicados = conflicto visible | §8, §21.18. |

## Interfaz

| Decisión | Motivo |
|---|---|
| Grupo «Empresa» en la barra lateral, encima de Trabajo; mismas piezas de Multica (tablas, pestañas, hojas laterales, tokens) | §5: misma aplicación, nueva estructura. |
| Colores de área como tokens del tema (`--area-*`), siempre con texto o icono al lado | Accesibilidad: el color nunca es la única señal. |
| El módulo Empresa tiene los textos en español directamente (excepción a `i18next/no-literal-string`) | Uso interno en español; el resto de la app está traducido al español con i18n completo. Si se distribuye en otros idiomas, mover los textos a un namespace `empresa`. |

## Pendiente de decisión del titular

- Licencia comercial / dispensa de marca de Multica: **no necesaria** para la prueba interna (confirmado por el titular el 19/10/2026).
- Distribución, Developer ID y notarización: fuera de alcance por ahora (uso interno).
- PostgreSQL embebido o servidor remoto para una versión instalable sin herramientas.
