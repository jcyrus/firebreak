#!/usr/bin/env zsh
# Builds a release Firebreak.app bundle into ./dist/Firebreak.app
# Required for interactive UserNotifications (they only work from a real .app bundle).
#
# Usage: ./scripts/bundle-app.sh [--install] [signing-identity]
#   --install  Copy to /Applications/Firebreak.app and register it as the only Launch Services
#              copy. macOS 26+ needs this to list Firebreak under System Settings › Menu Bar;
#              stale copies (dist/, DerivedData, archives) otherwise hide the menu bar icon.
set -euo pipefail

INSTALL=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL=1
  shift
fi

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

# Info.plist is shared with the Xcode target and contains $(VAR) build settings that only
# Xcode expands; resolve them here or the app ships with a literal "$(PRODUCT_BUNDLE_IDENTIFIER)".
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.jcyrus.firebreak" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.jcyrus.firebreak" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleName string Firebreak" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleName Firebreak" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string Firebreak" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Firebreak" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.developer-tools" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :LSApplicationCategoryType public.app-category.developer-tools" "$APP/Contents/Info.plist"

if grep -q '\$(' "$APP/Contents/Info.plist"; then
  echo "error: unresolved build variable in $APP/Contents/Info.plist:" >&2
  grep '\$(' "$APP/Contents/Info.plist" >&2
  exit 1
fi

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

if (( INSTALL )); then
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
  DEST=/Applications/Firebreak.app

  pkill -x Firebreak 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  codesign --verify --deep --strict "$DEST"

  # Unregister every other copy with this bundle id so Control Center resolves to /Applications.
  "$LSREGISTER" -dump 2>/dev/null \
    | awk '/^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); print }' \
    | grep -iE '/(Firebreak|FirebreakApp)\.app$' \
    | grep -vx "$DEST" \
    | while IFS= read -r stale; do
        "$LSREGISTER" -u "$stale" 2>/dev/null && echo "Unregistered stale copy: $stale"
      done || true  # no stale copies → grep exits 1, which pipefail would treat as fatal
  # Launch Services registers the freshly signed dist/ copy asynchronously, often after the sweep
  # above has run, so drop it explicitly.
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
  "$LSREGISTER" -f -R "$DEST"

  echo "Installed $DEST"
  echo "Run with: open \"$DEST\""
else
  echo "Run with: open \"$APP\" (or rerun with --install to put it in /Applications)"
fi
