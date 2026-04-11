# FieldWhisperer

A native macOS voice-to-text utility.  
Hold **⌥Space** (Option+Space) to record, release to transcribe — the text is automatically pasted into the focused app.

---

## Features

- **⌥Space push-to-talk** — global hotkey works in any app, any window; no Input Monitoring required
- **Auto-paste** — transcribed text is inserted directly at the cursor in native apps (via Accessibility), and automatically pasted via Cmd+V in Electron apps (Slack, Claude, browsers); text is always on clipboard as a fallback
- **Floating soundwave** — animated panel at the top-centre of your screen shows recording state, live transcription preview, and completion feedback
- **Menu bar icon** — mic lives in the Apple menu bar; no Dock icon
- **Remove filler words** — optional filter strips "um", "uh", "hmm" and similar from transcriptions
- **Powered by Whisper** — local, on-device transcription via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (no API keys, no cloud)
- **Model selector** — switch between Tiny / Base / Small / Medium from Settings

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

The app appears only in the menu bar (no Dock icon).

### Permissions

| Permission | Required? | Where to grant | Why |
|---|---|---|---|
| **Microphone** | ✅ Required | Prompted automatically on first recording | Capture your voice |
| **Accessibility** | Optional | System Settings → Privacy → Accessibility | Insert text directly at cursor; without it text is pasted via Cmd+V or left on clipboard |

> **Accessibility tip:** After each Xcode rebuild the binary changes — macOS de-trusts the old entry.  
> To re-grant: open System Settings → Accessibility, click **−** to remove FieldWhisperer, then **+** to re-add the freshly built app.

### First launch: model download

On first run the app downloads the Whisper model (~140 MB for the default *Small* model) from HuggingFace. The menu bar icon shows "Loading…" until complete. This is a one-time step; subsequent launches load from cache in under 3 seconds.

---

## Usage

1. Click into **any text field** in any app.
2. **Hold ⌥Space** — the floating soundwave appears at the top of your screen.
3. **Speak**.
4. **Release ⌥Space** — the soundwave shows "Transcribing…", then pastes the text automatically:
   - **Native apps** (Notes, Mail, TextEdit, Xcode, Terminal…): inserted directly at the cursor via Accessibility API.
   - **Electron / web apps** (Slack, Claude, browsers…): pasted automatically via Cmd+V.
   - **No text field was focused** (Finder, desktop): text is on your clipboard — press ⌘V manually.

---

## Running without Xcode

You only need Xcode once to build the app. After that, it runs independently.

1. In Xcode: **Product → Archive**
2. When the Organizer opens, click **Distribute App → Copy App**
3. Move **FieldWhisperer.app** to `/Applications`
4. Re-add it in **System Settings → Privacy & Security → Accessibility** (remove old entry, add new one — the path changed)
5. Launch from Spotlight or `/Applications` — Xcode never needs to be open again

Alternatively, grab the `.app` from DerivedData after a regular build:
```
~/Library/Developer/Xcode/DerivedData/FieldWhisperer-*/Build/Products/Debug/FieldWhisperer.app
```

---

## Settings

Click the menu bar icon → **Settings…**

### Transcription Model

| Model | Size | Best for |
|---|---|---|
| Tiny | ~40 MB | Fastest; great on Intel Macs |
| Base | ~75 MB | Fast; balanced |
| **Small** ✦ | ~140 MB | Default; great on all Macs |
| Medium | ~450 MB | Highest accuracy; Apple Silicon |

### Permissions panel

Shows current status of Microphone and Accessibility and provides quick links to the relevant System Settings panes.

---

## Architecture

```
AppDelegate (state machine: idle → recording → transcribing → idle)
├── HotKeyMonitor      Carbon RegisterEventHotKey (⌥Space, no Input Monitoring needed)
├── AudioRecorder      AVAudioEngine → 16 kHz mono Float32
├── TranscriptionEngine  WhisperKit wrapper (async, @MainActor)
├── TextInserter       AXUIElement primary; CGEventPostToPid Cmd+V fallback; clipboard always set
├── SoundwavePanel     NSPanel (.floating, .nonactivatingPanel)
│   └── SoundwaveView  SwiftUI animated bars / transcribing spinner / copied banner
└── MenuBarController  NSStatusItem + NSMenu
    └── SettingsWindowController → SettingsView (SwiftUI)
```

---

## Distribution

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
| ⌥Space does nothing | Wait for "Ready · Small" in the menu bar — model is still loading |
| ⌥Space does nothing (model ready) | Make sure no other app has grabbed ⌥Space (Alfred, Raycast, Spotlight) |
| Text not pasted automatically | Accessibility not granted — enable in System Settings → Privacy → Accessibility |
| Accessibility shows "Open Settings" despite being ON | Remove FieldWhisperer from the Accessibility list and re-add it (binary changed after rebuild) |
| "Model not loaded" in menu | Wait for download or check internet connection |
| No audio / mic not working | Grant **Microphone** in Settings panel or System Settings → Privacy → Microphone |
| App not in menu bar | Check Activity Monitor — if running, rebuild clean (⌘⇧K then ⌘R) |
