#!/usr/bin/env bash
set -euo pipefail

# Older per-user Xcode schemes may still call the installer as a post-build action.
if [[ -n "${XCODE_PRODUCT_BUILD_VERSION:-}" ]]; then
  echo "Use scripts/install_app.sh to install Pock."
  exit 0
fi

APP_PATH="${1:-}"
DESTINATION="${2:-/Applications/Pock.app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Pock Local Code Signing}"
EXPECTED_BUNDLE_IDENTIFIER="io.github.kalech7.pock-community"

if [[ "$(basename "$DESTINATION")" != *.app || -L "$DESTINATION" ]]; then
  echo "Expected an application bundle destination: $DESTINATION" >&2
  exit 65
fi

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

INSTALL_DIR="$(mktemp -d "$(dirname "$DESTINATION")/.pock-install.XXXXXX")"
STAGED_DESTINATION="$INSTALL_DIR/Pock.app"
PREVIOUS_DESTINATION="$INSTALL_DIR/previous.app"
cleanup() {
  if [[ -d "$PREVIOUS_DESTINATION" && ! -e "$DESTINATION" ]]; then
    mv "$PREVIOUS_DESTINATION" "$DESTINATION" || return
  fi
  rm -rf "$INSTALL_DIR"
}
trap cleanup EXIT
ditto "$APP_PATH" "$STAGED_DESTINATION"
codesign --verify --deep --strict --verbose=2 "$STAGED_DESTINATION"

pkill -x Pock 2>/dev/null || true
pkill -f "mediaremote-adapter\\.pl" 2>/dev/null || true

if [[ -d "$DESTINATION" ]]; then
  mv "$DESTINATION" "$PREVIOUS_DESTINATION"
fi
mv "$STAGED_DESTINATION" "$DESTINATION"

open "$DESTINATION"

HOOK_SCRIPT="$DESTINATION/Contents/Resources/pock-agent-activity.rb"
if [[ -f "$HOOK_SCRIPT" ]]; then
  /usr/bin/env -u RUBYOPT -u RUBYLIB /usr/bin/ruby --disable=gems "$HOOK_SCRIPT" codex --install
fi
