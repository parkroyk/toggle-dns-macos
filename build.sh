#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# The macOS 27 SDK expands SwiftUI's @State via the SwiftUIMacros macro plugin,
# which only full Xcode ships (Command Line Tools does not). If the active
# developer dir can't provide it, fall back to an installed Xcode.
has_plugin() {
    [ -f "$1/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ] || \
    [ -f "$1/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]
}
if ! has_plugin "$(xcode-select -p)"; then
    for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if has_plugin "$xcode/Contents/Developer"; then
            export DEVELOPER_DIR="$xcode"
            break
        fi
    done
fi

APP_NAME="ToggleDNS"
CONFIG="release"
DIST="dist"
APP_DIR="${DIST}/${APP_NAME}.app"

echo "==> Building (${CONFIG})…"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"

echo "==> Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

echo "==> Ad-hoc code signing…"
codesign --force --sign - "${APP_DIR}"

echo ""
echo "Done: ${APP_DIR}"
echo "Run with:  open ${APP_DIR}"
