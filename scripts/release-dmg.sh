#!/usr/bin/env zsh
# Creates a signed, notarized distributable DMG for Firebreak
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

VERSION="1.0.0"
DMG_NAME="Firebreak-${VERSION}.dmg"
DMG_PATH="$ROOT/dist/${DMG_NAME}"
STAGING="$ROOT/dist/dmg_staging"

echo "==> Step 1: Building and signing Firebreak.app..."
./scripts/bundle-app.sh

echo "==> Step 2: Preparing DMG staging directory..."
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"

cp -R "$ROOT/dist/Firebreak.app" "$STAGING/Firebreak.app"
ln -s /Applications "$STAGING/Applications"

echo "==> Step 3: Generating DMG..."
hdiutil create -volname "Firebreak" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

rm -rf "$STAGING"

SIGNING_ID="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | awk -F '"' '{print $2}')"

echo "==> Step 4: Signing DMG with Developer ID..."
codesign --force --sign "$SIGNING_ID" "$DMG_PATH"
codesign --verify --strict "$DMG_PATH"

PROFILE="${1:-}"

if [[ -n "${PROFILE}" ]]; then
  echo "==> Step 5: Submitting DMG to Apple Notary Service (profile: ${PROFILE})..."
  if xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait; then
    echo "==> Step 6: Notarization successful! Stapling ticket to DMG and App..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler staple "$ROOT/dist/Firebreak.app"
    echo "================================================================="
    echo "  SUCCESS! Firebreak DMG is notarized and ready for distribution:"
    echo "  $DMG_PATH"
    echo "================================================================="
  else
    echo "Notarization submission failed. Check log via: xcrun notarytool log <submission-id> --keychain-profile $PROFILE"
    exit 1
  fi
else
  echo "==> Step 5: Skipping Notarization (no profile provided)."
  echo "================================================================="
  echo "  Signed DMG built successfully at:"
  echo "  $DMG_PATH"
  echo "  To notarize with Apple, run: ./scripts/release-dmg.sh <keychain-profile>"
  echo "================================================================="
fi
