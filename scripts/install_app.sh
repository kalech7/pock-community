#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Pock.app}"
DESTINATION="${DESTINATION:-/Applications/${APP_NAME}}"
SKIP_LOCAL_SIGNING="${SKIP_LOCAL_SIGNING:-0}"

if [[ "$(basename "$DESTINATION")" != *.app || -L "$DESTINATION" ]]; then
  echo "Expected an application bundle destination: $DESTINATION" >&2
  exit 65
fi

cd "$ROOT_DIR"
export DEVELOPER_DIR

if [[ -f Podfile ]]; then
  pod install
fi

if [[ -z "$SCHEME" ]]; then
  SCHEME="$(xcodebuild -list -json -workspace Pock.xcworkspace | /usr/bin/ruby -rjson -e '
    schemes = JSON.parse(STDIN.read).fetch("workspace").fetch("schemes")
    puts(schemes.find { |name| name == "Pock" || name == "Pock (Pock project)" } || abort("Pock scheme not found"))
  ')"
fi

BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pock-community-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
xcodebuild \
  -workspace Pock.xcworkspace \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Could not find built app at DerivedData/Build/Products/${CONFIGURATION}/${APP_NAME}" >&2
  exit 1
fi

if [[ "$SKIP_LOCAL_SIGNING" != "1" ]]; then
  /usr/bin/env -u XCODE_PRODUCT_BUILD_VERSION "$ROOT_DIR/scripts/install_built_app.sh" "$APP_PATH" "$DESTINATION"
  exit
fi

rm -rf "$DESTINATION"
ditto "$APP_PATH" "$DESTINATION"
echo "Skipping local signing. macOS may ask for permissions again." >&2
open "$DESTINATION"

echo "Installed and opened ${DESTINATION}"
