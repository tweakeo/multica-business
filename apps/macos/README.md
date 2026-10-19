# TLS macOS host

Native AppKit app that runs the Multica desktop renderer inside `WKWebView`
instead of Electron. Context and status: [docs/tls/FASE-0.md](../../docs/tls/FASE-0.md).

## Build

```bash
apps/macos/scripts/prepare-artifacts.sh         # renderer, Go binaries, PostgreSQL (arm64), migrations
scripts/tls/build-demo-snapshot.sh              # bundle the demo (needs the dev database)
apps/macos/scripts/build.sh                     # signed Release .app
CONFIGURATION=Debug apps/macos/scripts/build.sh # Debug build (DebugHooks, Web Inspector)
scripts/tls/build-dmg.sh                        # dist/TLS-<version>.dmg and -debug.dmg
```

## Modes

`~/Library/Application Support/TLS/runtime-config.json`:

- `"mode": "embedded"` (default for a new install): `LocalStack` runs bundled
  PostgreSQL (Unix socket only), migrations and the API on `127.0.0.1:18080`,
  then signs in automatically. Data in `Application Support/TLS/runtime`, logs
  in `~/Library/Logs/TLS`, secrets in `runtime/secrets.env` (0600).
- `"mode": "external"`: use `apiUrl`/`wsUrl` (development server, see
  `scripts/tls/start-demo.sh`).

From Xcode: run `apps/macos/scripts/prepare-artifacts.sh` once (and after
renderer or Go changes), then open `TLS.xcodeproj` and run the `TLS` scheme.
`project.yml` is the source of truth; regenerate with `xcodegen generate`.

## Runtime

- Development against an external server: `scripts/tls/start-demo.sh`
  (PostgreSQL, backend, app in external mode). Usage guide:
  [docs/tls/GUIA-DEMO.md](../../docs/tls/GUIA-DEMO.md).
- An external server must allow the app origin: `CORS_ALLOWED_ORIGINS=...,tls-app://app`.
- Agent daemon profile: `~/.multica/profiles/tls-embedded/` (embedded) or
  `~/.multica/profiles/tls-local/` (external).
- Agent sandbox: the host writes `~/Library/Application Support/TLS/agent-sandbox.sb`
  and starts the daemon with `MULTICA_AGENT_SANDBOX_PROFILE`, so every agent
  process runs under `sandbox-exec` without access to `~/TLS Empresas`, daemon
  credentials, `.env` files or PostgreSQL. Restart the daemon after changing it.

## Layout

| Path | Role |
|---|---|
| `TLS/Web/AppSchemeHandler.swift` | Serves `Resources/renderer` at `tls-app://app/` |
| `TLS/Resources/bridge.js` | Recreates `desktopAPI` / `daemonAPI` / `updater` |
| `TLS/Web/NativeBridge.swift` | Allow-listed native actions, app origin only |
| `TLS/Services/DaemonManager.swift` | Bundled `multica` daemon supervision |
| `TLS/Services/LocalStack.swift` | Embedded PostgreSQL + migrations + API server, auto sign-in |
| `TLS/App/DebugHooks.swift` | Debug-only snapshot/eval hooks (`scripts/debug-hook.sh`) |
