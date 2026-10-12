#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Charmera Fixer.app"
ARCHS=(--arch arm64 --arch x86_64)
VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [[ ! -f Resources/AppIcon.icns ]]; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
  rm -rf "$ICONSET"
fi

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/CharmeraFixer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CharmeraFixer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/Charmera Fixer.app"
  cp -R "$APP" /Applications/
  echo "Installed Charmera Fixer $VERSION to /Applications"
else
  echo "Built $APP ($VERSION, build $BUILD_NUMBER)"
fi
