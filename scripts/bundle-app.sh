#!/usr/bin/env zsh
# Builds a release Firebreak.app bundle into ./dist/Firebreak.app
# Required for interactive UserNotifications (they only work from a real .app bundle).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release --product FirebreakApp

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/Firebreak.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/FirebreakApp" "$APP/Contents/MacOS/Firebreak"
cp "$ROOT/Sources/FirebreakApp/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Firebreak" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Firebreak" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run with: open \"$APP\""
