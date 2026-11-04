# Despliegue

Cómo montar y desplegar la app sin acceso a ningún Mac concreto. Hay cuatro formas, de menos a más trabajo. Todas arrancan con datos ficticios: no hace falta ningún dato real para probarla.

| Forma | Para qué | Plataforma |
|---|---|---|
| [1. Demo de desarrollo](#1-demo-de-desarrollo) | Programar y probar el fork | macOS o Linux |
| [2. Instancia aparte con una carpeta de empresa](#2-instancia-aparte-con-una-carpeta-de-empresa) | Usar la app con una carpeta propia, separada de la demo | macOS (Homebrew) |
| [3. App de macOS del fork (DMG)](#3-app-de-macos-del-fork-dmg) | Darla a alguien para que la use sin instalar nada | macOS 13+, Apple Silicon |
| [4. App nativa The Last System](#4-app-nativa-the-last-system) | La versión nativa en Swift | macOS 15+, Apple Silicon |

Las variables de entorno de cada forma están en [VARIABLES.md](VARIABLES.md) (sin valores), y cómo encajan las piezas, en [ARQUITECTURA.md](ARQUITECTURA.md).

## Requisitos

- Node 22 o posterior (pnpm vía corepack), Go 1.26 o posterior y PostgreSQL 17.
- Para las apps de macOS: Xcode 26 y XcodeGen. Para la nativa, Xcode 26.6.
- Opcional: [Claude Code](https://docs.anthropic.com/claude-code) con la sesión iniciada, para que los agentes ejecuten. Sin él funciona todo menos las ejecuciones.

## 1. Demo de desarrollo

```sh
pnpm install
brew services start postgresql@17          # o el PostgreSQL 17 que tengas
cp .env.example .env                        # rellena los valores: ver VARIABLES.md › Desarrollo
scripts/tls/run-backend.sh                  # migraciones y servidor en :8080
node scripts/tls/seed-demo.mjs --reset      # empresa ficticia «Asesoría Ribera» (--offline para no lanzar agentes)
pnpm dev:web                                # http://localhost:3000
```

Para entrar, usa `demo@tls.local` y el `MULTICA_DEV_VERIFICATION_CODE` de tu `.env`. Cómo se recorre la demo: [GUIA-DEMO.md](GUIA-DEMO.md).

El entorno gestionado de Multica (`make up` / `make down`) también sirve. Lee `CONTRIBUTING.md`.

## 2. Instancia aparte con una carpeta de empresa

`scripts/tls/the-last.sh` monta una instancia que no comparte nada con la demo: su propio clúster de PostgreSQL (solo por socket Unix), su API en `127.0.0.1` y su web. Lee y escribe una carpeta de empresa con la estructura «humana».

```sh
cp -R examples/empresa-ejemplo "$HOME/TLS/Mi empresa"     # parte de la carpeta de ejemplo
export TLS_INSTANCE_DIR="$HOME/Library/Application Support/TLS/Mi empresa"
export TLS_API_PORT=8091 TLS_WEB_PORT=3002
export TLS_COMPANY_FOLDER="$HOME/TLS/Mi empresa"
scripts/tls/the-last.sh start    # clúster, migraciones, API y web (compila la primera vez)
scripts/tls/the-last.sh setup    # usuario, espacio de trabajo, carpeta y reconstrucción desde la carpeta
scripts/tls/the-last.sh abrir    # abre el navegador con la sesión iniciada (enlace local de un solo uso, 60 s)
scripts/tls/the-last.sh status | stop | build
```

- Los secretos (`JWT_SECRET` y el código de acceso) se generan la primera vez en `$TLS_INSTANCE_DIR/secrets.env`, con permisos 0600. No van en `.env` ni en el repositorio.
- La carpeta es la verdad: la base de datos se puede reconstruir desde ella. **No uses nunca la carpeta de una empresa real para probar.**
- Necesita Homebrew `postgresql@17` en `/opt/homebrew/opt/postgresql@17`.

## 3. App de macOS del fork (DMG)

Una app que lleva dentro PostgreSQL 17, el servidor Go, la interfaz y la demo. Detalles: [`apps/macos/README.md`](../../apps/macos/README.md).

```sh
apps/macos/scripts/prepare-artifacts.sh    # interfaz, binarios Go y PostgreSQL embebido
scripts/tls/build-demo-snapshot.sh         # congela la demo para meterla en la app
apps/macos/scripts/build.sh                # TLS.app (Release) firmada
scripts/tls/build-dmg.sh                   # TLS-<versión>.dmg y TLS-<versión>-debug.dmg
```

- **Firma:** cada persona firma con su propio equipo de Apple. Sin «Developer ID» ni notarización, macOS bloquea la primera apertura. Se abre desde *Ajustes del Sistema › Privacidad y seguridad › Abrir igualmente*, o con `xattr -dr com.apple.quarantine /Applications/TLS.app`.
- Guarda su estado en `~/Library/Application Support/TLS/`, los registros en `~/Library/Logs/TLS/` y la carpeta de la demo en `~/TLS Empresas/`.

## 4. App nativa The Last System

En [`apps/the-last-system/`](../../apps/the-last-system/README.md). Es código propio, con su licencia (ver su `LICENSE`).

```sh
cd apps/the-last-system
make bootstrap    # comprueba Xcode y xcodegen y resuelve dependencias
make firma        # escribe Config/Signing.local.xcconfig con TU equipo de Apple (no se versiona)
make test         # swift test de TLSKit y compilación de la app
make dmg          # dist/The-Last-System-<versión>.dmg y sus sumas SHA-256
make verify       # firma, permisos, DMG y sandbox
```

Para distribuirla a terceros sin el aviso de Gatekeeper hacen falta el programa de desarrolladores de pago (certificado «Developer ID Application») y `xcrun notarytool`.

## Servidor para varias personas (sin hacer todavía)

Hoy las formas 2 a 4 son de un solo Mac y una sola persona escribiendo. Para alojarlo en un servidor, la base es la de Multica: `docker-compose.selfhost.yml` y [`SELF_HOSTING.md`](../../SELF_HOSTING.md). Al menos falta:

- decidir dónde vive la carpeta de la empresa, porque hoy la lee el servidor desde su disco local;
- correo real (SMTP o Resend) en lugar del código de desarrollo;
- `APP_ENV=production` y secretos fuertes.

## Licencia

El fork deriva de Multica y está bajo la [Multica License](../../LICENSE) (Apache 2.0 con condiciones adicionales). **Usarlo internamente está permitido.** Alojarlo para terceros o venderlo como producto requiere una licencia comercial de Index Labs (Hong Kong) Limited. La interfaz conserva el nombre, el logo y los avisos de Multica.

`apps/the-last-system/` no deriva de Multica y tiene su propia licencia.
