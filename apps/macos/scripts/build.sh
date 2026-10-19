#!/usr/bin/env bash
# One-shot build: web + Go artifacts, Xcode project, signed Release .app.
#   apps/macos/scripts/build.sh            # Release
#   CONFIGURATION=Debug apps/macos/scripts/build.sh
# Output: apps/macos/build/DerivedData/Build/Products/<Config>/TLS.app
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"

"$HERE/scripts/prepare-artifacts.sh"

if command -v xcodegen >/dev/null 2>&1; then
  (cd "$HERE" && xcodegen generate --quiet)
fi

xcodebuild \
  -project "$HERE/TLS.xcodeproj" \
  -scheme TLS \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$HERE/build/DerivedData" \
  -destination 'platform=macOS,arch=arm64' \
  build

echo "==> $HERE/build/DerivedData/Build/Products/$CONFIGURATION/TLS.app"
