#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
DESTINATION="${2:-/Applications/Pock.app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Pock Local Code Signing}"
EXPECTED_BUNDLE_IDENTIFIER="io.github.kalech7.pock-community"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Built app not found: ${APP_PATH:-<empty>}" >&2
  exit 66
fi

if ! security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
  echo "Code signing identity not found: ${SIGNING_IDENTITY}" >&2
  echo "Refusing to install an unsigned build because macOS may ask for permissions again." >&2
  exit 69
fi

BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$BUNDLE_IDENTIFIER" != "$EXPECTED_BUNDLE_IDENTIFIER" ]]; then
  echo "Unexpected bundle identifier: ${BUNDLE_IDENTIFIER:-<missing>}" >&2
  exit 65
fi

unset SWIFT_DEBUG_INFORMATION_FORMAT SWIFT_DEBUG_INFORMATION_VERSION
"$ROOT_DIR/scripts/sign_app.sh" "$APP_PATH"

designated_requirement() {
  codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'
}

NEW_REQUIREMENT="$(designated_requirement "$APP_PATH")"
if [[ -z "$NEW_REQUIREMENT" ]]; then
  echo "Signed build has no designated requirement." >&2
  exit 65
fi
if [[ -d "$DESTINATION" ]]; then
  CURRENT_REQUIREMENT="$(designated_requirement "$DESTINATION" || true)"
  if [[ -z "$CURRENT_REQUIREMENT" || "$CURRENT_REQUIREMENT" != "$NEW_REQUIREMENT" ]]; then
    echo "Refusing to replace Pock with a different designated requirement." >&2
    exit 65
  fi
fi

STAGED_DESTINATION="${DESTINATION}.installing.$$"
trap 'rm -rf "$STAGED_DESTINATION"' EXIT
rm -rf "$STAGED_DESTINATION"
ditto "$APP_PATH" "$STAGED_DESTINATION"
codesign --verify --deep --strict --verbose=2 "$STAGED_DESTINATION"

pkill -x Pock 2>/dev/null || true
pkill -f "mediaremote-adapter\\.pl" 2>/dev/null || true

rm -rf "$DESTINATION"
mv "$STAGED_DESTINATION" "$DESTINATION"
trap - EXIT

open "$DESTINATION"
