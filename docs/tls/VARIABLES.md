# Variables de entorno

Solo nombres, para qué sirven y de dónde salen. **Ningún valor real va en el repositorio**: `.env` y `secrets.env` están en `.gitignore`, y los secretos se generan en cada instalación.

## Desarrollo (`.env`, a partir de `.env.example`)

Las de Multica están documentadas en [`.env.example`](../../.env.example). Para el fork, como mínimo:

| Variable | Para qué | Notas |
|---|---|---|
| `DATABASE_URL` | Conexión a PostgreSQL 17 | La base de desarrollo es `multica` |
| `APP_ENV` | `development` en local | En un servidor, `production` |
| `JWT_SECRET` | Firma las sesiones | **Secreto.** Aleatorio y largo, distinto en cada entorno |
| `MULTICA_DEV_VERIFICATION_CODE` | Código fijo para entrar sin correo | **Solo en desarrollo.** En producción se usa correo real (SMTP o Resend) |
| `CORS_ALLOWED_ORIGINS` | Orígenes que pueden llamar a la API | Añade `tls-app://app` para la app de macOS en modo externo |
| `FF_PROJECT_WORKFLOWS_V1` | Flujos de proyecto de Multica. Los scripts de TLS lo activan siempre | `true` |
| `FRONTEND_ORIGIN`, `MULTICA_APP_URL`, `MULTICA_PUBLIC_URL` | URL de la web y de la API | |
| `DO_NOT_TRACK`, `ANALYTICS_DISABLED` | Sin analítica | `1` y `true` en local |

## Capa de empresa (servidor)

| Variable | Para qué | Por defecto |
|---|---|---|
| `TLS_STATE_DIR` | Dónde guarda el servidor el estado local de cada empresa (escritor único, diario). Nunca dentro de la carpeta de la empresa | `~/Library/Application Support/TLS` |
| `TLS_LOCAL_LOGIN_FILE` | Fichero 0600 del que la API lee (y borra) el enlace local de un solo uso de `the-last.sh abrir`. Sin él, no hay enlace | sin definir |
| `AUTH_TOKEN_TTL` | Duración de la sesión (duración de Go o segundos) | la de Multica |
| `MULTICA_SECRETS_FILE` | Fichero `KEY=valor` (0600) que el servidor carga al arrancar. Así los secretos no pasan por el entorno del proceso, que los agentes del mismo usuario podrían leer. Lo ya definido en el entorno manda | sin definir |
| `TLS_REBIND_AGENTS` | Con `1`, el ciclo de eventos reasigna a un runtime en línea los agentes de la empresa que no lo tienen | sin definir |

## Instancia aparte (`scripts/tls/the-last.sh`)

| Variable | Para qué | Por defecto |
|---|---|---|
| `TLS_COMPANY_FOLDER` | Carpeta de la empresa que lee y escribe la instancia | ninguno: **obligatoria** |
| `TLS_INSTANCE_DIR` | Estado de la instancia: clúster de PostgreSQL, `secrets.env`, `run/` y `uploads/` | `~/Library/Application Support/TLS/The Last` |
| `TLS_API_PORT`, `TLS_WEB_PORT` | Puertos de la API (solo `127.0.0.1`) y de la web | `8090` y `3001` |
| `TLS_EMAIL`, `TLS_NAME` | Usuario de la instancia y su nombre visible | `direccion@tls.local` y `Dirección` |

`JWT_SECRET` y `MULTICA_DEV_VERIFICATION_CODE` los genera `the-last.sh` en `$TLS_INSTANCE_DIR/secrets.env`. Los scripts `.mjs` reciben `TLS_API` y `TLS_CODE` del propio `the-last.sh`, así que no hace falta definirlos.

## Demo (`scripts/tls/seed-demo.mjs`)

| Variable | Para qué | Por defecto |
|---|---|---|
| `TLS_API` | API contra la que se siembra | `http://localhost:8080` |
| `TLS_EMAIL` | Usuario de la demo | `demo@tls.local` |
| `TLS_CODE` | Código de acceso | el `MULTICA_DEV_VERIFICATION_CODE` de `.env` |

## App nativa (`apps/the-last-system`)

No usa `.env`. Las claves de otros programas van en el **Llavero** de macOS (servicio `es.thelast.system.gateway`). La firma va en `Config/Signing.local.xcconfig` (`DEVELOPMENT_TEAM`), que no se versiona. En pruebas, `TLS_APP_SUPPORT` y `TLS_EMPRESAS` cambian dónde guarda el estado y las empresas, y con `TLS_EXIGIR_FIRMA=1`, `make dmg` falla si la firma es ad hoc.
