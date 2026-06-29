#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Pock Local Code Signing}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 /path/to/Pock.app" >&2
  exit 64
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
  echo "Code signing identity not found: ${SIGNING_IDENTITY}" >&2
  echo "Install the same local signing certificate or set SIGNING_IDENTITY." >&2
  exit 69
fi

APP_NAME="$(basename "$APP_PATH")"
NESTED_APP="$APP_PATH/$APP_NAME"

if [[ -d "$NESTED_APP" ]]; then
  echo "Removing accidental nested bundle: $NESTED_APP"
  rm -rf "$NESTED_APP"
fi

codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d -r- "$APP_PATH" 2>&1
