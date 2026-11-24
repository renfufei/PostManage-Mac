#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="PostManage"

for tool in swift xcodegen xcodebuild hdiutil ditto codesign; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

cd "$ROOT_DIR"
echo "Generating app icon…"
swift scripts/generate_icon.swift "$ROOT_DIR"

echo "Generating Xcode project…"
xcodegen generate >/dev/null

echo "Building Release app…"
xcodebuild \
  -project PostManage.xcodeproj \
  -scheme PostManage \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build -quiet

SOURCE_APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Build succeeded but app was not found: $SOURCE_APP" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
rm -rf "$DIST_DIR/$APP_NAME.app" "$DIST_DIR/$APP_NAME.dmg"
ditto "$SOURCE_APP" "$DIST_DIR/$APP_NAME.app"
codesign --force --deep --sign - "$DIST_DIR/$APP_NAME.app"
codesign --verify --deep --strict "$DIST_DIR/$APP_NAME.app"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/postmanage-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$DIST_DIR/$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$DIST_DIR/$APP_NAME.dmg" >/dev/null
hdiutil verify "$DIST_DIR/$APP_NAME.dmg" >/dev/null

echo "Done:"
echo "  $DIST_DIR/$APP_NAME.app"
echo "  $DIST_DIR/$APP_NAME.dmg"
