# QuickNote

A small macOS app for catching ideas the moment they show up.
Tap **⌃ Control + ⌥ Option** together, from any app, and a floating capture panel opens.
Type the idea, press **esc** or **⌘↩**, and it's saved. The app you were in gets focus back.

While the panel is open, tap **right Shift** to flip back through earlier notes (newest first), and edit them in place.
After the oldest note it wraps around to the new one, and whatever you'd typed there is kept:

```
⌃⌥ → New note → right ⇧ → Note 3 → right ⇧ → Note 2 → right ⇧ → Note 1 → right ⇧ → New note …
```

Only a quick tap on its own counts: holding right Shift to type a capital letter never switches notes.

Browse and edit all notes in the main window (Dock icon, or the 💡 menu bar icon → *Open QuickNote*).

## Install
Paste into Terminal:

```sh
curl -fsSL https://gabrielesarria167-ai.github.io/QuickNote/install.sh | bash
```

Files fetched with curl aren't quarantined, so macOS opens the app without the "could not verify" warning.
Or [download QuickNote.dmg](https://github.com/gabrielesarria167-ai/QuickNote/releases/latest/download/QuickNote.dmg)
and drag it into Applications. It isn't notarized, so the first launch needs System Settings › Privacy & Security ›
**Open Anyway**. Run the command again to update; add `-s -- --uninstall` after `bash` to remove the app
(your notes are kept).

The download page is [gabrielesarria167-ai.github.io/QuickNote](https://gabrielesarria167-ai.github.io/QuickNote/).

## Requirements
- macOS 15+
- Xcode 16+ (developed with Xcode 26)

## Build & install
```sh
scripts/make_signing_identity.sh   # once per Mac: creates the "QuickNote Signing" certificate
./build.sh --install               # release build → /Applications/QuickNote.app, relaunched
```

`./build.sh` without `--install` only builds into `build/Release/`. Tests:

```sh
xcodebuild -project QuickNote.xcodeproj -scheme QuickNote -derivedDataPath build test
```

The project uses folder-synchronized groups, so new files added under `QuickNote/` are picked up automatically.

## Accessibility permission (granted once)
macOS only lets an app see key presses in other apps once it has been allowed under
**System Settings → Privacy & Security → Accessibility**. QuickNote asks on first launch and shows a banner
in the main window until you allow it. The shortcut turns on by itself once you do; no restart is needed.

macOS remembers that permission by the app's signature. An ad-hoc signature is a hash of one exact build, so
every rebuild looked like a new app. Release builds are therefore signed with the self-signed
**QuickNote Signing** certificate every time (same trick as MacSafe), and an update keeps the permission.
Back up `~/Library/QuickNote Signing`: on another Mac import `identity.p12` (password `quicknote`) into the
login keychain instead of making a new certificate. A different certificate means allowing it once more.
Without the certificate `build.sh` falls back to ad-hoc signing and says so.

### Debug builds (Xcode ⌘R)
Debug builds are **QuickNote Dev** (`com.gabrielesarria.quicknote.debug`): signed ad hoc, with their own
Accessibility entry and their own notes, so they never disturb the installed app. The hardened runtime only
loads code from the same Apple Developer team, and a self-signed certificate has none. Debug builds load
extra code (Xcode's debug library and the test bundle), so they can't use the certificate. Their permission
may need re-ticking after a rebuild; quit the installed QuickNote while running Dev so both don't react to
the same ⌃⌥.

Notes live in `~/Library/Application Support/<bundle id>/Notes.store`.

## Releasing
1. Bump `MARKETING_VERSION` in the QuickNote target's build settings.
2. `./build.sh --release` (refuses to build without the "QuickNote Signing" certificate, so every release keeps
   people's Accessibility permission).
3. `gh release create v<version> dist/* --title "QuickNote <version>"`, ending the notes with
   `**Download page:** [gabrielesarria167-ai.github.io/QuickNote](https://gabrielesarria167-ai.github.io/QuickNote/)`.
   `install.sh` always fetches `QuickNote.zip` from the latest release; the page links its `QuickNote.dmg`.
4. Push `main`. The site is served by GitHub Pages from `docs/` on `main`: `index.html` (download page) and
   `install.sh` (the installer).

The app icon is drawn in `scripts/icon.svg`; `swift scripts/make_icon.swift` renders it into the asset catalog.

## How it works
| Piece | File |
| --- | --- |
| ⌃⌥ detection (pure, unit tested) | `QuickNote/Hotkey/ModifierChordDetector.swift` |
| Global/local key listeners | `QuickNote/Hotkey/HotkeyMonitor.swift` |
| Right-Shift tap detection (pure, unit tested) | `QuickNote/Hotkey/ModifierTapDetector.swift` |
| Floating capture panel + note rotation | `QuickNote/Capture/` |
| Notes list + editor | `QuickNote/Main/` |
| SwiftData model | `QuickNote/Model/Note.swift` |

- Keys are only *observed*, never swallowed: every key still reaches the app you're typing in.
- ⌃⌥ counts as a **tap**: the panel opens when you release them, only if no other key (or ⇧/⌘) was pressed
  while they were held and the whole tap took ≤ 0.8 s. Shortcuts that start with ⌃⌥ (⌃⌥→ in window managers,
  VoiceOver commands) keep working and never open the panel.
- Tapping ⌃⌥ again while the panel is open saves and closes it.
- To change the keys or timing, edit `chord` / `maxDuration` in `ModifierChordDetector`.

## Renaming the app
The visible name comes from `INFOPLIST_KEY_CFBundleDisplayName` in the target's build settings
(Debug and Release each have one).
For a complete rename, also change `PRODUCT_BUNDLE_IDENTIFIER` and rename the target/scheme in Xcode.
Changing the bundle identifier starts a new, empty notes database and needs the Accessibility permission again.
