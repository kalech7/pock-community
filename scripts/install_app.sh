#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SCHEME="${SCHEME:-Pock (Pock project)}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Pock.app}"
DESTINATION="${DESTINATION:-/Applications/${APP_NAME}}"
SKIP_LOCAL_SIGNING="${SKIP_LOCAL_SIGNING:-0}"

cd "$ROOT_DIR"

if [[ -f Podfile ]]; then
  pod install
fi

DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -workspace Pock.xcworkspace \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/Build/Products/${CONFIGURATION}/${APP_NAME}" \
    -type d \
    -print0 |
  xargs -0 ls -td |
  head -n 1
)"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Could not find built app at DerivedData/Build/Products/${CONFIGURATION}/${APP_NAME}" >&2
  exit 1
fi

rm -rf "$DESTINATION"
ditto "$APP_PATH" "$DESTINATION"

if [[ "$SKIP_LOCAL_SIGNING" != "1" ]]; then
  "$ROOT_DIR/scripts/sign_app.sh" "$DESTINATION"
else
  echo "Skipping local signing. macOS may ask for permissions again." >&2
fi

open "$DESTINATION"

echo "Installed and opened ${DESTINATION}"
