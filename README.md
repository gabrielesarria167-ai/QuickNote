# QuickNote

A small macOS app for catching ideas the moment they show up.
Tap **⌃ Control + ⌥ Option** together, from any app, and a floating capture panel opens.
Type the idea, press **esc** or **⌘↩**, and it's saved. The app you were in gets focus back.

While the panel is open, press **`.` and `-` together** to flip back through earlier notes (newest first), and edit
them in place. After the oldest note it wraps around to the new one, and whatever you'd typed there is kept:

```
⌃⌥ → New note → .- → Note 3 → .- → Note 2 → .- → Note 1 → .- → New note …
```

Press **`<` and `z` together** to go the other way, towards newer notes (from the new note it wraps to the oldest).

Neither character is typed when you press them together. Typed on their own, `.`, `-`, `<` and `z` work as usual: each
is held back for 70 ms to see whether the other key of its pair joins it, too short to notice.

### Voice notes
Press **⌃⌥R** from any app to dictate a note; a small pill near the top of the screen (just under the capture
panel when that's open) shows the level, the time and the words as they're recognized. Press **⌃⌥R** again (or the pill's ■) to stop and save; ✕ throws the recording away.
The transcript goes to:

- the note shown in the capture panel, **appended** as a new paragraph, if the panel is open when you start;
- the note open in the main window, appended, if that window is in front;
- otherwise a **new note** (and the main window selects it).

The main window also has a mic button next to *New Note*: it records into the selected note, or makes a new one.

Recognition uses Apple's Speech framework in your system language, **on your Mac** when the language supports it
(otherwise Apple's servers). Apple limits each recognition request to about a minute, so a long recording is
stitched together from several: the audio moves to a fresh request at a pause after 45 s (at 55 s regardless),
and the words are put back in order. A long pause or a stitch can occasionally add a full stop where you didn't
pause. A recording stops by itself after 30 minutes. If you unplug the microphone it switches to the new
microphone, or stops and saves if none is left; the same if the recognizer keeps failing.

The first recording asks for **Microphone** and **Speech Recognition** access. Allow both under System Settings →
Privacy & Security; the pill tells you where if one is off. The permission prompt takes focus from the capture
panel and closes it (saving what you typed), so that first transcript is added to the note the panel was on, or
becomes a new note if it was on the new one.

### Any language, with a title (Gemini)
Apple's on-device recognizer listens in one language. Add a Google **Gemini** API key and each voice note is also
transcribed by Gemini when you stop: in whatever language you spoke, including a mix of several (say, Italian
and Japanese in one note), with paragraphs and a short **title** on the first line (`# Title`). The title goes above
the transcript whether it becomes a new note or is appended to an open one.

1. Get a key in [Google AI Studio](https://aistudio.google.com/apikey).
2. Open the **Settings** window (⌘, in QuickNote, or the menu bar icon → *Settings…*), paste the key under *Gemini* and press *Save*.
   The key is kept in your login Keychain and is never shown again; *Remove* deletes it.
3. Pick a model: *Gemini 3.8 Flash* (best, the default), *Gemini 3.5 Flash-Lite* (cheaper) or any model id under
   *Custom…*.

While it works the pill says *Transcribing…* and shows Apple's text. ■ saves Apple's text at once without waiting;
✕ throws the recording away, and needs a second press within 3 seconds, since there is no way back.

**Nothing is lost when Gemini fails.** If Gemini can't be used (no connection, quota reached, the key or model was
rejected, an error), the note is saved with Apple's on-device text and the recording is moved to
`~/Library/Application Support/<bundle id>/Unsent Recordings/` (named by date, e.g. `2026-10-10 14.03.22.aac`).
The pill stays until you dismiss it and offers **Retry**, **Show in Finder** and, for a rejected key or model,
**Open Settings**. Retry sends the kept recording again to the same place; if the note already has Apple's text,
Gemini's goes below it as its own `# Title` block (a recording made into a new note gets a second note). The file is
deleted only after a successful retry. While files wait, the menu bar icon has an *Unsent Recordings (n)…* item
that opens the folder. If Apple's recognizer gave up during a long recording (the pill says *Listening — text
after you stop*), ■ becomes *Stop waiting — keep the recording*, since the audio is then the only full copy.
A recording Gemini says has no speech in it, or one shorter than half a second, is not kept, unless it is longer than 30 seconds or Apple's text is incomplete (Gemini may be wrong then).

**Quitting** (⌘Q or the menu) while a recording is going or waiting for Gemini saves Apple's text to its note and
moves the audio to Unsent Recordings, so you can retry it later.

*On-device recognition* in Settings picks the language of Apple's recognizer (Automatic follows your system
language). It is what you see while you speak, and the text of the note when there is no key or Gemini fails.

**Privacy.** Without a key everything stays on your Mac (or goes to Apple's servers if your language has no
on-device recognition). With a key, each voice note's audio is sent to Google's Gemini API. On the free tier Google
may use it to improve its products and people may review it; on a paid tier it doesn't ([terms](https://ai.google.dev/gemini-api/terms)).
The audio is written to a temporary file only while there is a key and deleted once Gemini has answered or you
discard it; if Gemini fails it is kept in Unsent Recordings (see above) until a retry succeeds or you delete it.
After a crash, the next launch moves whatever recording it left in the temporary folder (if it holds more than a few
seconds of audio) to Unsent Recordings too. A recording is sent in one
request, so the limit is about 14 MB of audio, far more than the 30 minute recording limit needs.

### Formatting
Notes are plain Markdown, shown styled as you type: once a style is complete its marks are hidden, and a list of them sits under the editor. The caret steps over hidden marks, and backspace after a bullet, to-do or title mark turns the line back into plain text.

| Type | Or select text and use the toolbar | Shortcut |
| --- | --- | --- |
| `# Title` | Title | |
| `- item` | List | |
| `[ ] to-do` (click the box to tick it) | To-do | |
| `**bold**` | Bold | ⌘B |
| `_italic_` or `*italic*` | Italic | ⌘I |
| `~~strike~~` | Strikethrough | ⇧⌘X |
| `==highlight==` | Highlight | ⇧⌘H |

Browse and edit all notes in the main window (Dock icon, or the 💡 menu bar icon → *Open QuickNote*). The menu bar
icon turns into a 🎙 while a voice note is being recorded or transcribed.

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
(Needed for ⌃⌥ and ⌃⌥R in other apps. The mic button and ⌃⌥R inside QuickNote work without it.)

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
| `.` + `-` chord detection (pure, unit tested) | `QuickNote/Hotkey/KeyChordDetector.swift` |
| ⌃⌥R detection (pure, unit tested) | `QuickNote/Hotkey/RecordShortcut.swift` |
| Floating capture panel + note rotation | `QuickNote/Capture/` |
| Stitching the pieces of a long recording, when to switch (pure, unit tested) | `QuickNote/Voice/SegmentedTranscript.swift`, `SegmentScheduler.swift` |
| Where a recording goes, language choice, pill text (pure, unit tested) | `QuickNote/Voice/RecordTarget.swift`, `RecognizerLocale.swift`, `TranscriptExcerpt.swift` |
| Microphone + speech recognition | `QuickNote/Voice/VoiceRecorder.swift`, `AudioTap.swift`, `SpeechPermissions.swift` |
| Gemini request, answer, retries and limits (pure parts unit tested) | `QuickNote/Voice/Gemini/GeminiRequest.swift`, `GeminiResponse.swift`, `GeminiTranscriber.swift` |
| Gemini or Apple text, pill notices (pure, unit tested) | `QuickNote/Voice/Gemini/TranscriptChoice.swift`, `GeminiNotice.swift`, `QuickNote/Voice/VoiceNoteText.swift` |
| API key in the Keychain | `QuickNote/Voice/Gemini/KeyStore.swift` |
| Writing the audio as 16 kHz mono AAC while recording | `QuickNote/Voice/AudioFileWriter.swift` |
| Unsent Recordings folder, keep-or-delete rule, double-press ✕ (pure parts unit tested) | `QuickNote/Voice/UnsentRecordings.swift`, `ConfirmPress.swift` |
| Settings window (an `NSWindow` owned by `AppDelegate`, opened by ⌘, / menu bar / the pill) and the values behind it | `QuickNote/Settings/SettingsView.swift`, `QuickNote/Voice/VoiceSettings.swift` |
| Recording pill (never key, so the panel stays open) | `QuickNote/Voice/RecordingPill.swift` |
| Starting/stopping a recording, saving the transcript | `QuickNote/Voice/VoiceCaptureController.swift` |
| Which note the main window shows | `QuickNote/Voice/OpenNoteTracker.swift`, `QuickNote/Main/WindowReader.swift` |
| Adding a paragraph to note text (pure, unit tested) | `QuickNote/Model/NoteText.swift` |
| Markdown parser (pure, unit tested), styled editor, selection toolbar | `QuickNote/Editor/` |
| Notes list + editor | `QuickNote/Main/` |
| SwiftData model | `QuickNote/Model/Note.swift` |

- Keys are only *observed*, never swallowed: every key still reaches the app you're typing in. ⌃⌥R is observed
  too, so in other apps they receive it as well (most ignore ⌃⌥R). Only inside QuickNote it is dropped, so it isn't
  typed into the editor.
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
