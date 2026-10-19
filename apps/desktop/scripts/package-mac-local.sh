#!/usr/bin/env bash
# Local macOS build for this fork, signed with the "Apple Development"
# certificate from the Xcode keychain (no Developer ID / notarization).
#
#   pnpm --filter @multica/desktop package:mac:local          # arm64
#   pnpm --filter @multica/desktop package:mac:local --x64    # Intel
#
# Override the identity with CSC_NAME="Apple Development: Name (ID)".
# Output: apps/desktop/dist/mac-<arch>/Multica.app + .dmg/.zip
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH="${1:---arm64}"

if [[ -z "${CSC_NAME:-}" ]]; then
  CSC_NAME="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"Apple Development: \(.*\)"/\1/p' | head -1)"
fi
if [[ -z "$CSC_NAME" ]]; then
  echo "No 'Apple Development' identity found in the keychain." >&2
  echo "Open Xcode > Settings > Accounts > Manage Certificates to create one." >&2
  exit 1
fi
export CSC_NAME
echo "[package-mac-local] signing with: Apple Development: $CSC_NAME"

# Without APPLE_TEAM_ID scripts/package.mjs already skips notarization.
unset APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD

node scripts/package.mjs --mac "$ARCH" -c.mac.type=development --publish never
