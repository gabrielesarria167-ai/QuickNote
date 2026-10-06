#!/bin/bash
# QuickNote installer for macOS.
#
#   curl -fsSL https://gabrielesarria167-ai.github.io/QuickNote/install.sh | bash
#   curl -fsSL https://gabrielesarria167-ai.github.io/QuickNote/install.sh | bash -s -- --uninstall
#
# Installs QuickNote.app into Applications. Files fetched with curl aren't quarantined, so macOS opens
# the app without the "could not verify" Gatekeeper warning. Running it again updates the app; your
# notes and the Accessibility permission are kept.
#
# Options: --uninstall   remove the app (your notes are kept; the message says where)
#          --update      update without questions, and reopen the app if it was open
#          --yes         don't ask questions
# For testing: QUICKNOTE_ZIP=<local zip>  QUICKNOTE_DEST=<app folder>
set -euo pipefail

REPO="gabrielesarria167-ai/QuickNote"
APP_NAME="QuickNote.app"
ZIP_URL="https://github.com/$REPO/releases/latest/download/QuickNote.zip"
NOTES_DIR="$HOME/Library/Application Support/com.gabrielesarria.quicknote"
MIN_MACOS=15

UNINSTALL=0; UPDATE=0; ASK=1
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    --update) UPDATE=1; ASK=0 ;;
    --yes|-y) ASK=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
[[ -r /dev/tty ]] || ASK=0

bold=$'\033[1m'; dim=$'\033[2m'; red=$'\033[31m'; green=$'\033[32m'; blue=$'\033[34m'; off=$'\033[0m'
[[ -t 1 ]] || { bold=""; dim=""; red=""; green=""; blue=""; off=""; }
step() { printf '%s→%s %s\n' "$blue" "$off" "$*"; }
ok()   { printf '%s✓%s %s\n' "$green" "$off" "$*"; }
note() { printf '  %s%s%s\n' "$dim" "$*" "$off"; }
die()  { printf '%s✗ %s%s\n' "$red" "$*" "$off" >&2; exit 1; }
ask()  {  # ask "question" → 0 for yes (default yes)
  [[ $ASK == 1 ]] || return 1
  local reply; printf '%s [Y/n] ' "$1"; read -r reply </dev/tty || return 1
  [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

TESTING=0; [[ -n "${QUICKNOTE_DEST:-}" ]] && TESTING=1   # a test install never touches the real one
WAS_RUNNING=0
quit_app() {  # quits QuickNote and remembers whether it was open
  [[ $TESTING == 1 ]] && return 0
  if pgrep -af "$APP_NAME/Contents/MacOS/QuickNote" >/dev/null 2>&1; then
    WAS_RUNNING=1
    osascript -e 'tell application id "com.gabrielesarria.quicknote" to quit' >/dev/null 2>&1 || true
    sleep 1
    pkill -af "$APP_NAME/Contents/MacOS/QuickNote" 2>/dev/null || true
  fi
  return 0
}

# ── uninstall ────────────────────────────────────────────────────────────────
if [[ $UNINSTALL == 1 ]]; then
  quit_app
  if [[ $TESTING == 1 ]]; then
    targets=("$QUICKNOTE_DEST/$APP_NAME")
  else
    targets=("/Applications/$APP_NAME" "$HOME/Applications/$APP_NAME")
  fi
  for p in "${targets[@]}"; do
    [[ -e "$p" ]] || continue
    rm -rf "$p" && ok "Removed $p"
  done
  ok "QuickNote is uninstalled."
  if [[ -d "$NOTES_DIR" && $TESTING == 0 ]]; then
    note "Your notes are still in $NOTES_DIR"
    note "Delete that folder too if you don't want them any more."
  fi
  exit 0
fi

if [[ $UPDATE == 1 ]]; then
  printf '\n%sUpdating QuickNote%s\n\n' "$bold" "$off"
else
  printf '\n%sQuickNote installer%s\n\n' "$bold" "$off"
fi

# ── 1. this Mac ──────────────────────────────────────────────────────────────
[[ "$(uname -s)" == Darwin ]] || die "QuickNote only runs on macOS."
macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= MIN_MACOS )) || die "QuickNote needs macOS $MIN_MACOS or later (this Mac has $macos)."
ok "macOS $macos on $(uname -m)"

# ── 2. the app ───────────────────────────────────────────────────────────────
if [[ -n "${QUICKNOTE_DEST:-}" ]]; then
  DEST="$QUICKNOTE_DEST"
elif [[ -w /Applications ]]; then
  DEST="/Applications"
else
  DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

if [[ -n "${QUICKNOTE_ZIP:-}" ]]; then
  cp "$QUICKNOTE_ZIP" "$TMP/app.zip"
  [[ -f "$QUICKNOTE_ZIP.sha256" ]] && cp "$QUICKNOTE_ZIP.sha256" "$TMP/app.zip.sha256"
else
  step "Downloading QuickNote…"
  curl -fL --progress-bar -o "$TMP/app.zip" "$ZIP_URL" || die "Couldn't download $ZIP_URL"
  curl -fsL -o "$TMP/app.zip.sha256" "$ZIP_URL.sha256" || die "Couldn't download the checksum for the app."
fi
if [[ -f "$TMP/app.zip.sha256" ]]; then
  want="$(awk '{print $1}' "$TMP/app.zip.sha256")"
  have="$(shasum -a 256 "$TMP/app.zip" | awk '{print $1}')"
  [[ "$want" == "$have" ]] || die "The download is damaged (checksum mismatch). Nothing was installed."
  ok "Download verified"
fi

ditto -x -k "$TMP/app.zip" "$TMP/unzipped"
[[ -d "$TMP/unzipped/$APP_NAME" ]] || die "The download doesn't contain $APP_NAME."
quit_app
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/unzipped/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true
# Same path, new bundle: macOS keeps showing the old icon until the app is re-registered.
touch "$DEST/$APP_NAME"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST/$APP_NAME" >/dev/null 2>&1 || true
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/$APP_NAME/Contents/Info.plist" 2>/dev/null || true)"
ok "Installed QuickNote ${VERSION:+$VERSION }in $DEST"

# ── 3. done ──────────────────────────────────────────────────────────────────
if [[ $UPDATE == 1 ]]; then
  printf '\n%sQuickNote is up to date.%s\n' "$bold$green" "$off"
  [[ $WAS_RUNNING == 1 ]] && { open "$DEST/$APP_NAME" || true; }
  exit 0
fi

printf '\n%sAll set.%s Tap %s⌃ Control + ⌥ Option%s together, from any app, to write an idea down.\n\n' \
  "$bold$green" "$off" "$bold" "$off"
note "The first time, QuickNote asks for Accessibility access so it can notice ⌃⌥ in other apps:"
note "System Settings › Privacy & Security › Accessibility › turn on QuickNote. Updates keep it on."
if [[ $WAS_RUNNING == 1 ]]; then
  open "$DEST/$APP_NAME" || true
elif [[ $TESTING == 0 ]] && ask "Open QuickNote now?"; then
  open "$DEST/$APP_NAME" || true
fi
