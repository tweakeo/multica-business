#!/usr/bin/env bash
# Builds and runs the Go backend with the checkout's .env (local TLS dev).
# Requires PostgreSQL running (brew services start postgresql@17).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/server"
set -a; . "$ROOT/.env"; set +a
go run ./cmd/migrate up
go build -o bin/server ./cmd/server
exec ./bin/server
