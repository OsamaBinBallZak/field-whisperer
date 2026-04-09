# FieldWhisperer

A native macOS voice-to-text utility inspired by WhisperFlow.  
Hold **⌥Space** (Option+Space) to record, release to transcribe, and the text lands in your clipboard — or directly in the focused field if Accessibility is granted.

---

## Features

- **⌥Space push-to-talk** — global hotkey works in any app, any window; no Input Monitoring required
- **Floating soundwave** — animated panel at the top-centre of your screen shows recording state
- **Always on clipboard** — transcribed text is always copied; if Accessibility is granted it also inserts directly at the cursor
- **"Copied! ⌘V to paste" feedback** — when direct insertion isn't available, the panel shows a green banner so you always know the text is ready
- **Menu bar icon** — mic lives in the Apple menu bar; no Dock icon
- **Powered by Whisper** — local, on-device transcription via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (no API keys, no cloud)
- **Model selector** — switch between Tiny / Base / Small / Medium from Settings

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | **14.0 Sonoma** |
| Xcode | **15.0** |
| Hardware | Any Mac (Apple Silicon recommended for speed) |

---

## Quick Start

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
| **Accessibility** | Optional | System Settings → Privacy → Accessibility | Insert text directly at cursor; without it text is copied to clipboard instead |

> **Accessibility tip:** After each Xcode rebuild the binary changes — macOS de-trusts the old entry.  
> To re-grant: open System Settings → Accessibility, click **−** to remove FieldWhisperer, then **+** to re-add the freshly built app.

### First launch: model download

On first run the app downloads the Whisper model (~140 MB for the default *Small* model) from HuggingFace. The menu bar icon shows "Loading…" until complete. This is a one-time step; subsequent launches load from cache in under 3 seconds.

---

## Usage

1. Click into **any text field** in any app.
2. **Hold ⌥Space** — the floating soundwave appears at the top of your screen.
3. **Speak**.
4. **Release ⌥Space** — the soundwave shows "Transcribing…", then:
   - If **Accessibility is granted**: text is inserted directly at the cursor.
   - Otherwise: the panel shows **"Copied! ⌘V to paste"** — just press ⌘V.

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
├── TextInserter       AXUIElement primary; clipboard fallback (always copies text)
├── SoundwavePanel     NSPanel (.floating, .nonactivatingPanel)
│   └── SoundwaveView  SwiftUI animated bars / transcribing spinner / copied banner
└── MenuBarController  NSStatusItem + NSMenu
    └── SettingsWindowController → SettingsView (SwiftUI)
```

---

## Distribution (outside App Store)

FieldWhisperer ships **without App Sandbox** because `AXUIElement` (Accessibility) is blocked by the sandbox.

To distribute:
1. Set your Team in Signing & Capabilities.
2. Archive: **Product → Archive**.
3. Notarize via Xcode Organizer or `xcrun notarytool`.
4. Export as a **Developer ID** signed `.app`, wrap in a `.dmg`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| ⌥Space does nothing | Wait for "Ready · Small" in the menu bar — model is still loading |
| ⌥Space does nothing (model ready) | Make sure no other app has grabbed ⌥Space (Alfred, Raycast, Spotlight) |
| Text not inserted at cursor | Accessibility not granted — text is still on clipboard, press ⌘V |
| Accessibility shows "Open Settings" despite being ON | Remove FieldWhisperer from the Accessibility list and re-add it (binary changed after rebuild) |
| "Model not loaded" in menu | Wait for download or check internet connection |
| No audio / mic not working | Grant **Microphone** in Settings panel or System Settings → Privacy → Microphone |
| App not in menu bar | Check Activity Monitor — if running, rebuild clean (⇧⌘K then ⌘R) |
