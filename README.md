# FieldWhisperer

A native macOS voice-to-text utility.  
Hold **⌥Space** (Option+Space) to record, release to transcribe — the text is automatically pasted into the focused app.

---

## Features

- **⌥Space push-to-talk** — global hotkey works in any app, any window; no Input Monitoring required
- **Toggle mode** — optionally switch to tap-to-start / tap-to-stop in Settings (great for long recordings)
- **Auto-paste** — transcribed text is inserted directly at the cursor in native apps (via Accessibility), and automatically pasted via Cmd+V in Electron apps (Slack, Claude, browsers); text is always on clipboard as a fallback
- **Pastes to last-focused field** — click into a different field while recording and the text goes there on release
- **Floating soundwave** — animated panel at the top-centre of your screen shows recording state, live transcription preview, and completion feedback
- **Menu bar only** — lives in the Apple menu bar; no Dock icon
- **Remove filler words** — optional filter strips "um", "uh", "hmm" and similar from transcriptions
- **Powered by Parakeet V3** — local, on-device transcription via [FluidAudio](https://github.com/FluidInference/FluidAudio) + NVIDIA Parakeet (no API keys, no cloud, ~10x faster than Whisper)
- **Model selector** — switch between Parakeet V3 (multilingual, 25 languages) and V2 (English-optimized) from Settings

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | **14.0 Sonoma** |
| Hardware | Any Mac (Apple Silicon recommended for speed) |

> To build from source: **Xcode 15.0** or later is required.

---

## Quick Start (build from source)

```bash
git clone https://github.com/itsHendri/field-whisperer.git
cd field-whisperer
open FieldWhisperer.xcodeproj
```

1. In Xcode, select the **FieldWhisperer** scheme and your Mac as destination.
2. Go to **Signing & Capabilities → Team** and pick your Apple Developer team.
3. Press **⌘R** to build and run.

The app appears in the menu bar (no Dock icon).

### Permissions

| Permission | Required? | Where to grant | Why |
|---|---|---|---|
| **Microphone** | ✅ Required | Prompted automatically on first recording | Capture your voice |
| **Accessibility** | Optional | System Settings → Privacy → Accessibility | Insert text directly at cursor; without it text is pasted via Cmd+V or left on clipboard |

> **Accessibility tip:** After each Xcode rebuild the binary changes — macOS de-trusts the old entry.  
> To re-grant: open System Settings → Accessibility, click **−** to remove FieldWhisperer, then **+** to re-add the freshly built app.

### First launch: model download

On first run the app downloads the Parakeet V3 model (~494 MB) from HuggingFace. The menu bar icon shows "Loading…" until complete. This is a one-time step; subsequent launches load from cache in under 3 seconds.

---

## Usage

### Push-to-talk (default)

1. Click into **any text field** in any app.
2. **Hold ⌥Space** — the floating soundwave appears at the top of your screen.
3. **Speak**.
4. **Release ⌥Space** — the soundwave shows "Transcribing…", then pastes the text automatically:
   - **Native apps** (Notes, Mail, TextEdit, Xcode, Terminal…): inserted directly at the cursor via Accessibility API.
   - **Electron / web apps** (Slack, Claude, browsers…): pasted automatically via Cmd+V.
   - **No text field was focused** (Finder, desktop): text is on your clipboard — press ⌘V manually.

> **Tip:** You can click into a different field *while recording* — the text will paste wherever the cursor is when you release.

### Toggle mode (for long recordings)

Switch to toggle mode in **Settings → Activation**:

1. **Tap ⌥Space** — recording starts.
2. **Speak** for as long as you like — no need to hold the key.
3. **Tap ⌥Space again** — transcription runs and text is pasted.

---

## Running without Xcode

You only need Xcode once to build the app. After that it runs independently.

1. In Xcode press **⌘B** to build
2. In the menu bar: **Product → Show Build Folder in Finder**
3. Open **Products → Debug** — you'll see **FieldWhisperer.app**
4. Drag it to `/Applications`
5. Open **System Settings → Privacy & Security → Accessibility** — remove the old FieldWhisperer entry, click **+** and add the one from `/Applications`
6. Launch from Spotlight (⌘Space → "Field") — Xcode never needs to be open again

> Or open the Debug folder directly from Terminal:
> ```bash
> open ~/Library/Developer/Xcode/DerivedData/FieldWhisperer-*/Build/Products/Debug/
> ```

---

## Settings

Click the menu bar icon → **Settings…**

### Transcription Model

| Model | Size | Best for |
|---|---|---|
| **Parakeet V3** ✦ | ~494 MB | Default; multilingual (25 European languages); ~10x faster than Whisper |
| Parakeet V2 | ~476 MB | English-optimized; slightly faster for English-only use |

### Activation

| Mode | Behaviour |
|---|---|
| **Push-to-talk** (default) | Hold ⌥Space to record, release to transcribe |
| **Toggle** | Tap ⌥Space to start, tap again to transcribe |

### Permissions panel

Shows current status of Microphone and Accessibility and provides quick links to the relevant System Settings panes.

---

## Architecture

```
AppDelegate (state machine: idle → recording → transcribing → idle)
├── HotKeyMonitor      Carbon RegisterEventHotKey (⌥Space, no Input Monitoring needed)
├── AudioRecorder      AVAudioEngine → 16 kHz mono Float32
├── TranscriptionEngine  FluidAudio/Parakeet wrapper (async, @MainActor)
├── TextInserter       AXUIElement primary; CGEventPostToPid Cmd+V fallback; clipboard always set
├── SoundwavePanel     NSPanel (.floating, .nonactivatingPanel)
│   └── SoundwaveView  SwiftUI animated bars / transcribing spinner / copied banner
└── MenuBarController  NSStatusItem + NSMenu
    └── SettingsWindowController → SettingsView (SwiftUI)
```

---

## Distribution

### Share with a friend

#### Option A — DMG (recommended, most polished)

Run the included build script from the project root:

```bash
bash Distribution/create-dmg.sh
```

This builds a Release `.app`, signs it ad-hoc, and produces **FieldWhisperer.dmg** on your Desktop. Send the DMG via AirDrop, Google Drive, or email.

Recipient steps:
1. Double-click the DMG — a Finder window opens showing the app and an Applications shortcut
2. Drag **FieldWhisperer** onto **Applications**
3. **Right-click → Open** on first launch (Gatekeeper bypass — only needed once)
4. Grant **Microphone** and **Accessibility** permissions
5. Wait for "Ready · Parakeet V3" in the menu bar (model downloads once, ~494 MB)

#### Option B — Zip (quickest)

1. Right-click **FieldWhisperer.app** in `/Applications` → **Compress**
2. Send the `.zip` via AirDrop, email, or Google Drive
3. Friend unzips and drags to their `/Applications`
4. Friend **right-clicks → Open** to bypass Gatekeeper (only needed once)

#### Gatekeeper bypass options

If right-click → Open doesn't work, try one of these:

**Terminal command (most reliable):**
```bash
xattr -cr /Applications/FieldWhisperer.app
```
Then double-click to open normally.

**System Settings:**
1. Try to open the app (it will be blocked)
2. Go to **System Settings → Privacy & Security**
3. Scroll down — you'll see "FieldWhisperer was blocked"
4. Click **Open Anyway**

> **Mac mini / no built-in mic:** Connect AirPods or a USB microphone *before* launching the app. Check **System Settings → Sound → Input** and confirm the mic is selected. The app shows "No microphone detected" in the floating panel if no input device is found.

### App Store — not viable

FieldWhisperer uses APIs that are blocked by the App Store sandbox:
- `AXUIElement` — direct text insertion via Accessibility
- `CGEventPostToPid` — targeted Cmd+V simulation
- Carbon `RegisterEventHotKey` — global hotkey without Input Monitoring

Shipping to the App Store would require replacing all three mechanisms — effectively a rewrite.

### Recommended: Developer ID + GitHub Releases

| Method | Cost | Notes |
|---|---|---|
| **Developer ID signed DMG** | $99/yr ([Apple Developer Program](https://developer.apple.com/programs/)) | Standard for indie Mac apps; passes Gatekeeper; users just double-click |
| **Homebrew Cask** | Free (once DMG exists) | `brew install --cask field-whisperer`; ideal for developer audience |
| **Direct share (.zip / AirDrop)** | Free | Unsigned; recipients must right-click → Open to bypass Gatekeeper; fine for testing with friends |

**Steps to create a distributable build:**
1. Set your Developer ID team in **Signing & Capabilities**
2. **Product → Archive**
3. Organizer → **Distribute App → Developer ID → Export**
4. Notarize: `xcrun notarytool submit FieldWhisperer.app --wait`
5. Wrap in a `.dmg` and upload to GitHub Releases

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| ⌥Space does nothing | Wait for "Ready" in the menu bar — model is still loading |
| ⌥Space does nothing (model ready) | Make sure no other app has grabbed ⌥Space (Alfred, Raycast, Spotlight) |
| Text not pasted automatically | Accessibility not granted — enable in System Settings → Privacy → Accessibility |
| Accessibility shows "Open Settings" despite being ON | Remove FieldWhisperer from the Accessibility list and re-add it (binary changed after rebuild) |
| "Model not loaded" in menu | Wait for download or check internet connection |
| No audio / mic not working | Grant **Microphone** in Settings panel or System Settings → Privacy → Microphone |
| App not in menu bar | Check Activity Monitor — if running, rebuild clean (⌘⇧K then ⌘R) |
| "No microphone detected" shown in panel | No input device found — connect AirPods or USB mic, then try again |
| AirPods connected but mic not recording | Open System Settings → Sound → Input and manually select AirPods as input; Bluetooth auto-selection is unreliable |
| Mac mini / external mic not working | Connect mic *before* pressing the hotkey; check System Settings → Sound → Input shows it selected |
