#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-0.9.5}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE="MoveFolders_v0.3.swift"
BASE_ICON="MoveFolders_v0.3.3.icns"
APP_NAME="MoveFolders"
ARTIFACT_NAME="MoveFolders_v${VERSION}"
APP_DIR="${APP_NAME}.app"
EXECUTABLE="$APP_NAME"
BUNDLE_ID="com.thomasbriet.movefolders"
PKG_ID="com.thomasbriet.movefolders.pkg"
PKG_SCRIPTS_DIR=".build/pkg-scripts"

rm -rf "$APP_DIR" "${APP_NAME}.bin" "${ARTIFACT_NAME}.bin" "${ARTIFACT_NAME}_installer.pkg" "${ARTIFACT_NAME}_share.zip" "$PKG_SCRIPTS_DIR"

swiftc -target arm64-apple-macosx11.0 "$SOURCE" -o "${ARTIFACT_NAME}.bin" -framework AppKit -framework Foundation -framework NetFS -framework ServiceManagement

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "${ARTIFACT_NAME}.bin" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "$BASE_ICON" "$APP_DIR/Contents/Resources/${APP_NAME}.icns"

/usr/bin/plutil -create xml1 "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string MoveFolders" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $EXECUTABLE" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}.icns" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $APP_NAME" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string MoveFolders" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 11.0" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_DIR/Contents/Info.plist"

find "$APP_DIR" -name '._*' -type f -delete
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

mkdir -p "$PKG_SCRIPTS_DIR"
cat > "$PKG_SCRIPTS_DIR/postinstall" <<'SCRIPT'
#!/bin/sh
set -u

for old_app in /Applications/MoveFolders_v*.app; do
  [ -e "$old_app" ] || continue
  rm -rf "$old_app" || true
done

exit 0
SCRIPT
chmod 755 "$PKG_SCRIPTS_DIR/postinstall"

COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --keepParent "$APP_DIR" "${ARTIFACT_NAME}_share.zip"
COPYFILE_DISABLE=1 pkgbuild \
  --component "$APP_DIR" \
  --install-location /Applications \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --scripts "$PKG_SCRIPTS_DIR" \
  "${ARTIFACT_NAME}_installer.pkg"

ls -lh "$APP_DIR" "${ARTIFACT_NAME}_share.zip" "${ARTIFACT_NAME}_installer.pkg"
