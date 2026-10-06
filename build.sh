#!/bin/bash
# Builds QuickNote.app.
#   ./build.sh             release build into build/Release/QuickNote.app
#   ./build.sh --install   … and put it in /Applications, then relaunch it
#   ./build.sh --release   … plus dist/QuickNote.zip and QuickNote.dmg (each with a .sha256) for a GitHub Release
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"
MODE="${1:-}"

# Signed with the same certificate every time (scripts/make_signing_identity.sh makes it), so macOS
# sees a rebuild as the same app and it keeps the Accessibility permission; an ad-hoc signature is
# new on every build.
SIGN_ID="QuickNote Signing"
SIGN_ARGS=()
if ! security find-certificate -c "$SIGN_ID" >/dev/null 2>&1; then
  if [[ "$MODE" == "--release" ]]; then
    echo "No \"$SIGN_ID\" certificate: a release signed without it makes everyone turn Accessibility" >&2
    echo "back on. Import the backup from ~/Library/$SIGN_ID, or run scripts/make_signing_identity.sh." >&2
    exit 1
  fi
  echo "  (no \"$SIGN_ID\" certificate: signing ad hoc, so the Accessibility permission won't survive a rebuild."
  echo "   Run scripts/make_signing_identity.sh, or import ~/Library/$SIGN_ID/identity.p12 from a backup.)"
  SIGN_ARGS=(CODE_SIGN_IDENTITY=-)
fi

echo "→ building"
xcodebuild -project QuickNote.xcodeproj -scheme QuickNote -configuration Release -destination generic/platform=macOS \
  -derivedDataPath "$ROOT/build/DerivedData" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build -quiet
APP="$ROOT/build/Release/QuickNote.app"
rm -rf "$APP" && mkdir -p "$(dirname "$APP")"
ditto "$ROOT/build/DerivedData/Build/Products/Release/QuickNote.app" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true))"

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"

if [[ "$MODE" == "--release" ]]; then
  DIST="$ROOT/dist"
  rm -rf "$DIST" && mkdir -p "$DIST"
  # The zip is what docs/install.sh downloads; people downloading in a browser get the disk image.
  ditto -c -k --keepParent --norsrc --noextattr --noqtn "$APP" "$DIST/QuickNote.zip"

  echo "→ disk image"
  STAGE="$ROOT/build/dmg"
  rm -rf "$STAGE" && mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/QuickNote.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "QuickNote" -srcfolder "$STAGE" -fs HFS+ -format UDZO \
    -imagekey zlib-level=9 -ov "$DIST/QuickNote.dmg"

  (cd "$DIST" && shasum -a 256 QuickNote.zip > QuickNote.zip.sha256 && shasum -a 256 QuickNote.dmg > QuickNote.dmg.sha256)
  echo "Release $VERSION:"
  echo "  $DIST/QuickNote.dmg   (browser download)"
  echo "  $DIST/QuickNote.zip   (install.sh)"
  echo "Upload them with their .sha256 files to a GitHub Release, e.g.:"
  echo "  gh release create v$VERSION dist/* --title \"QuickNote $VERSION\""
fi

if [[ "$MODE" == "--install" ]]; then
  DEST="/Applications/QuickNote.app"
  osascript -e 'tell application id "com.gabrielesarria.quicknote" to quit' >/dev/null 2>&1 || true
  pkill -f "QuickNote.app/Contents/MacOS/QuickNote" 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
