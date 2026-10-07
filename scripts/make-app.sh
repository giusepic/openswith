#!/usr/bin/env bash
# Build a distributable OpensWith.app bundle from a release build.
#
# Output: dist/OpensWith.app and dist/OpensWith.zip
# Requirements: Swift toolchain (Command Line Tools or Xcode). No Xcode-specific
# tooling — just `swift build`, `cp`, and `zip`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="OpensWith"
BUNDLE_DIR="dist/${APP_NAME}.app"
ZIP_PATH="dist/${APP_NAME}.zip"
INFO_PLIST_SOURCE="Distribution/Info.plist"
ICONSET_SOURCE="Distribution/AppIcon.iconset"

echo "==> Building release binary"
swift build -c release

BINARY_PATH=".build/release/${APP_NAME}"
if [[ ! -f "$BINARY_PATH" ]]; then
    echo "ERROR: expected binary at $BINARY_PATH but it doesn't exist" >&2
    exit 1
fi

echo "==> Assembling ${BUNDLE_DIR}"
rm -rf "dist"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp "$BINARY_PATH" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"
cp "$INFO_PLIST_SOURCE" "${BUNDLE_DIR}/Contents/Info.plist"

echo "==> Building AppIcon.icns"
if [[ ! -d "$ICONSET_SOURCE" ]]; then
    echo "ERROR: missing iconset at $ICONSET_SOURCE" >&2
    exit 1
fi
iconutil --convert icns "$ICONSET_SOURCE" --output "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"

# Ad-hoc sign the binary so macOS will run it locally without quarantine
# blocking on every launch. This is NOT real code signing — Gatekeeper will
# still prompt on first launch for downloaded copies. Distribution builds
# coming from a CI/release machine should be signed and notarized.
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "==> Creating ${ZIP_PATH}"
( cd dist && zip -r -q "${APP_NAME}.zip" "${APP_NAME}.app" )

echo
echo "Done."
echo "  App:  ${REPO_ROOT}/${BUNDLE_DIR}"
echo "  Zip:  ${REPO_ROOT}/${ZIP_PATH}"
echo
echo "Test locally:  open ${BUNDLE_DIR}"
