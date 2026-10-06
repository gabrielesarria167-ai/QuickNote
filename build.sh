#!/bin/bash
# Builds QuickNote.app.
#   ./build.sh             release build into build/Release/QuickNote.app
#   ./build.sh --install   … and put it in /Applications, then relaunch it
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

if [[ "$MODE" == "--install" ]]; then
  DEST="/Applications/QuickNote.app"
  osascript -e 'tell application id "com.gabrielesarria.quicknote" to quit' >/dev/null 2>&1 || true
  pkill -f "QuickNote.app/Contents/MacOS/QuickNote" 2>/dev/null && sleep 1 || true
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
