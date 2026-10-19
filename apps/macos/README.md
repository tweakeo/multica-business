# TLS macOS host

Native AppKit app that runs the Multica desktop renderer inside `WKWebView`
instead of Electron. Context and status: [docs/tls/FASE-0.md](../../docs/tls/FASE-0.md).

## Build

```bash
apps/macos/scripts/build.sh                     # renderer + Go CLI + signed Release .app
CONFIGURATION=Debug apps/macos/scripts/build.sh # Debug build (includes DebugHooks)
```

From Xcode: run `apps/macos/scripts/prepare-artifacts.sh` once (and after
renderer or Go changes), then open `TLS.xcodeproj` and run the `TLS` scheme.
`project.yml` is the source of truth; regenerate with `xcodegen generate`.

## Runtime

- Server endpoints: `~/Library/Application Support/TLS/runtime-config.json`
  (created with `localhost` defaults on first launch).
- The server must allow the app origin: `CORS_ALLOWED_ORIGINS=...,tls-app://app`.
- Agent daemon profile: `~/.multica/profiles/tls-local/`.

## Layout

| Path | Role |
|---|---|
| `TLS/Web/AppSchemeHandler.swift` | Serves `Resources/renderer` at `tls-app://app/` |
| `TLS/Resources/bridge.js` | Recreates `desktopAPI` / `daemonAPI` / `updater` |
| `TLS/Web/NativeBridge.swift` | Allow-listed native actions, app origin only |
| `TLS/Services/DaemonManager.swift` | Bundled `multica` daemon supervision |
| `TLS/App/DebugHooks.swift` | Debug-only snapshot/eval hooks (`scripts/debug-hook.sh`) |
