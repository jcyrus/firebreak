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
if [[ -f "$ROOT/Sources/FirebreakApp/AppIcon.icns" ]]; then
  cp "$ROOT/Sources/FirebreakApp/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Firebreak" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Firebreak" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.developer-tools" "$APP/Contents/Info.plist"

# Detect Developer ID Application identity
SIGNING_ID="${1:-$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | awk -F '"' '{print $2}' || echo "-")}"

if [[ -z "$SIGNING_ID" ]]; then
  SIGNING_ID="-"
fi

echo "Signing with identity: $SIGNING_ID (Hardened Runtime)..."
codesign --force --deep --options runtime \
  --entitlements "$ROOT/Sources/FirebreakApp/Firebreak.entitlements" \
  --sign "$SIGNING_ID" \
  "$APP"

codesign --verify --deep --strict "$APP"
echo "Signature verified successfully."

echo "Built $APP"
echo "Run with: open \"$APP\""
