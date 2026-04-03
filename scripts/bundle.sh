#!/bin/bash
set -euo pipefail

ARCH="${1:-$(uname -m)}"
APP_NAME="Vitrail"
BUNDLE_DIR="dist/${APP_NAME}.app"
DMG_DIR="dist/dmg"
DMG_PATH="dist/${APP_NAME}-${ARCH}.dmg"

echo "Building for ${ARCH}..."
swift build -c release --arch "$ARCH"

echo "Creating app bundle..."
rm -rf "$BUNDLE_DIR" "$DMG_DIR" "$DMG_PATH"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

cp ".build/release/${APP_NAME}" "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"
cp Info.plist "$BUNDLE_DIR/Contents/Info.plist"
cp Vitrail.icns "$BUNDLE_DIR/Contents/Resources/Vitrail.icns"

echo "Creating DMG..."
mkdir -p "$DMG_DIR"
cp -r "$BUNDLE_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_DIR"

echo "Done: $DMG_PATH"
