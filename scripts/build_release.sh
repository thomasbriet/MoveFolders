#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.5}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE="MoveFolders_v0.3.swift"
BASE_ICON="MoveFolders_v0.3.3.icns"
APP_NAME="MoveFolders_v${VERSION}"
APP_DIR="${APP_NAME}.app"
EXECUTABLE="$APP_NAME"
IDENTIFIER_VERSION="${VERSION//./}"
BUNDLE_ID="com.example.movefolders.v${IDENTIFIER_VERSION}"

rm -rf "$APP_DIR" "${APP_NAME}.bin" "${APP_NAME}_installer.pkg" "${APP_NAME}_share.zip"

swiftc "$SOURCE" -o "${APP_NAME}.bin" -framework AppKit -framework Foundation

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "${APP_NAME}.bin" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$BASE_ICON" "$APP_DIR/Contents/Resources/${APP_NAME}.icns"

/usr/bin/plutil -create xml1 "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string MoveFolders v${VERSION}" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}.icns" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string MoveFolders v${VERSION}" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 10.13" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_DIR/Contents/Info.plist"

find "$APP_DIR" -name '._*' -type f -delete
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent "$APP_DIR" "${APP_NAME}_share.zip"
COPYFILE_DISABLE=1 pkgbuild \
  --component "$APP_DIR" \
  --install-location /Applications \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  "${APP_NAME}_installer.pkg"

ls -lh "$APP_DIR" "${APP_NAME}_share.zip" "${APP_NAME}_installer.pkg"
