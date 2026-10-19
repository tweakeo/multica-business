#!/usr/bin/env bash
# Drives the Debug-build automation hooks (TLS/App/DebugHooks.swift).
#   debug-hook.sh snapshot            -> prints path of debug/snapshot.png
#   debug-hook.sh eval 'return document.title'
set -euo pipefail

DIR="$HOME/Library/Application Support/TLS/debug"
CMD="${1:?usage: debug-hook.sh snapshot|eval <js>}"
mkdir -p "$DIR"

post() {
  osascript -l JavaScript -e "ObjC.import('Foundation'); \$.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately('com.leonmag.tls.debug', '$1', \$(), true)" >/dev/null
}

case "$CMD" in
  snapshot)
    rm -f "$DIR/snapshot.png"
    post snapshot
    for _ in $(seq 1 50); do [ -f "$DIR/snapshot.png" ] && break; sleep 0.2; done
    echo "$DIR/snapshot.png"
    ;;
  eval)
    printf '%s' "${2:?missing js}" > "$DIR/eval.js"
    rm -f "$DIR/eval-result.json"
    post eval
    for _ in $(seq 1 100); do [ -f "$DIR/eval-result.json" ] && break; sleep 0.2; done
    cat "$DIR/eval-result.json"; echo
    ;;
esac
