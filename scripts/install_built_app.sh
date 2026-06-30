#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
DESTINATION="${2:-/Applications/Pock.app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Pock Local Code Signing}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Built app not found: ${APP_PATH:-<empty>}" >&2
  exit 66
fi

pkill -x Pock 2>/dev/null || true
pkill -f "mediaremote-adapter\\.pl" 2>/dev/null || true

rm -rf "$DESTINATION"
ditto "$APP_PATH" "$DESTINATION"

if security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
  unset SWIFT_DEBUG_INFORMATION_FORMAT SWIFT_DEBUG_INFORMATION_VERSION
  "$ROOT_DIR/scripts/sign_app.sh" "$DESTINATION"
else
  echo "warning: Code signing identity not found: ${SIGNING_IDENTITY}; opening unsigned app." >&2
fi

open "$DESTINATION"
