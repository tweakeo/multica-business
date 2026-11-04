# Arquitectura

## Dos apps y una misma carpeta

Hay dos programas para el mismo trabajo. Los dos parten de la misma idea: **la carpeta de la empresa, en Markdown y CSV, es la verdad**, y la base de datos es una proyección que se puede reconstruir desde ella.

| | Mika Business (fork) | The Last System (nativa) |
|---|---|---|
| Dónde | Todo el repositorio menos `apps/the-last-system/` | `apps/the-last-system/` |
| Tecnología | Multica (Go, Next.js y React) más la capa de empresa `server/internal/biz` y `packages/{core,views}/…/biz|empresa`; app de macOS con PostgreSQL embebido (`apps/macos`) | Swift 6 con SwiftUI y AppKit, el paquete `TLSKit` y SQLite como índice desechable |
| Datos | PostgreSQL más la carpeta (estructura demo o «humana») | La carpeta, con SQLite solo como índice |
| Agentes | Los de Multica, uno por área y coordinados por Dirección, con el CLI `multica biz`, aprobaciones, auditoría y sandbox | Tu Claude Code, a través de `tls-mcp`, en una caja cerrada |
| Versión | 0.1 más el uso real (registros, sesión local, bases, portal, metas) | 1.0.0 |
| Licencia | Multica License | Propia (`apps/the-last-system/LICENSE`) |

La nativa se escribió desde cero a partir de la especificación del fork (sala limpia, `apps/the-last-system/docs/PROCEDENCIA.md`). Sus planes están en `apps/the-last-system/docs/PLAN.md` y en `docs/F*-CONTRATOS.md`.

## Mapa del repositorio

```
apps/web, apps/desktop, apps/mobile, apps/docs   Multica (la web y el escritorio llevan las pantallas de Empresa)
apps/macos/                 app de macOS del fork: WKWebView, PostgreSQL embebido, servidor y daemon
apps/the-last-system/       app nativa The Last System (Swift)
server/internal/biz/        capa de empresa: áreas, CRM, entrega, finanzas, carpeta, escritor único, vistas
server/migrations/585–592   tablas biz_* e índices
packages/core/biz/          cliente de /api/biz, consultas y cálculo del ritmo
packages/views/empresa/     pantallas de Empresa (Dirección, Ventas, Entrega, Finanzas, bases, portal)
scripts/tls/                demo, instancia aparte (the-last.sh), importadores y DMG
scripts/privacidad/         escaneo de secretos y datos personales
docs/tls/                   esta documentación
docs/diseno/                sistema visual y marca
negocio/                    teoría TLB, áreas y sistemas genéricos, método
examples/empresa-ejemplo/   carpeta ficticia con la estructura «humana»
```

## La carpeta de la empresa

Seis áreas, cada una con `Área.md`, `Sistemas/` y `Recursos/`. Además están `Empresa.md`, `Buzón/` y `Archivo/`. La estructura se elige en `.tls/layout.json`: sin el fichero se usa la de la demo, y con `{"preset": "humana"}`, la de [`examples/empresa-ejemplo/`](../../examples/empresa-ejemplo/). El formato completo está en [FORMATOS.md](FORMATOS.md).

- **Escritor único.** Solo una instalación escribe en una carpeta a la vez. La marca está en `.tls/escritor.json` y el bloqueo, fuera de la carpeta.
- **No se borra nada.** Lo que se retira se mueve a `Archivo/<misma ruta>`.
- **El texto humano se respeta.** En las notas que escribió una persona, la app solo toca el frontmatter.
- **Registros únicos.** Los importes viven en `4 · Finanzas/Registros/{emitidas,recibidas,pagos}.csv` y el extracto bancario entra por `Registros/importar/*.csv`.
- **Fuera de la carpeta**, en `TLS_STATE_DIR`: base de datos, diario, bloqueos, secretos e índices.

## Reglas que hace cumplir el código

Salen de [`negocio/`](../../negocio/README.md):

- **Ninguna salida sin aprobación.** Enviar, emitir, publicar o confirmar dinero crea una aprobación que muestra el antes y el después, y su ejecución va atada a lo aprobado.
- **El proyecto nace del cobro confirmado.** Llega con las tareas de la plantilla del servicio.
- **La conciliación se propone; confirmarla es de una persona.**
- **Cada capacidad tiene su modo:** manual, asistido, supervisado o autónomo. Además hay un interruptor global y un modo de solo lectura.

## Seguridad

- La API y PostgreSQL solo escuchan en `127.0.0.1` o por socket Unix.
- Los secretos se generan en cada instalación (`secrets.env`, 0600) y se cargan con `MULTICA_SECRETS_FILE`, no por el entorno.
- Los agentes corren en `sandbox-exec`: no ven la carpeta de la empresa, los perfiles, el estado, los `.env` ni la base de datos. Solo pasan por la API.
- Los datos reales nunca entran en el repositorio. `scripts/privacidad/escanear.sh` lo comprueba en local y en cada pull request.
