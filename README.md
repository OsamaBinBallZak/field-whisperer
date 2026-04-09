# FieldWhisperer

A native macOS voice-to-text utility inspired by WhisperFlow.  
Hold **FN** to record, release to transcribe, and watch the text appear instantly in whatever field you have focused.

---

## Features

- **FN-key activation** — global hotkey works in any app, any window
- **Floating soundwave** — animated panel at the top-centre of your screen shows recording state
- **Menu bar icon** — mic icon lives in the Apple menu bar; no Dock icon
- **Powered by Whisper** — local, on-device transcription via [WhisperKit](https://github.com/argmaxinc/WhisperKit) (no API keys, no cloud)
- **Smart text insertion** — Accessibility API (primary) with Clipboard+Cmd-V fallback for every app
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

The app appears only in the menu bar (no Dock icon). On first launch:

### Grant permissions (one-time setup)

| Permission | Where to grant | Why |
|---|---|---|
| **Input Monitoring** | System Settings → Privacy → Input Monitoring | Detect FN key globally |
| **Accessibility** | System Settings → Privacy → Accessibility | Insert text into focused fields |
| **Microphone** | Prompted automatically on first recording | Capture your voice |

> **Tip:** After granting Accessibility permission you may need to quit and relaunch the app.

### First launch: model download

On the first run the app downloads the Whisper model (~140 MB for the default *Small* model) from HuggingFace. The menu bar icon shows "Loading…" until the download completes. This is a one-time step; subsequent launches load the model from cache in under 3 seconds.

---

## Usage

1. Click into **any text field** in any app.
2. **Hold FN** — the floating soundwave appears at the top of your screen.
3. **Speak**.
4. **Release FN** — the soundwave shows "Transcribing…", then the text is pasted at the cursor.

---

## Settings

Click the menu bar icon → **Settings…**

- **Transcription Model** — trade off speed vs. accuracy:

| Model | Size | Best for |
|---|---|---|
| Tiny | ~40 MB | Fastest; Intel Macs |
| Base | ~75 MB | Fast; balanced |
| **Small** ✦ | ~140 MB | Default; great on all Macs |
| Medium | ~450 MB | Highest accuracy; Apple Silicon |

- **Permissions** — shortcut buttons to open the relevant System Settings pane.

---

## Architecture

```
AppDelegate (state machine: idle → recording → transcribing → idle)
├── HotKeyMonitor      CGEventTap on flagsChanged / .maskSecondaryFn
├── AudioRecorder      AVAudioEngine → 16 kHz mono Float32
├── TranscriptionEngine  WhisperKit wrapper (async, @MainActor)
├── TextInserter       AXUIElement primary, NSPasteboard+Cmd-V fallback
├── SoundwavePanel     NSPanel (.floating, .nonactivatingPanel)
│   └── SoundwaveView  SwiftUI animated bars + transcribing spinner
└── MenuBarController  NSStatusItem + NSMenu
    └── SettingsWindowController → SettingsView (SwiftUI)
```

---

## Distribution (outside App Store)

FieldWhisperer intentionally ships **without App Sandbox** because both `CGEventTap` (Input Monitoring) and `AXUIElement` (Accessibility) are blocked by the sandbox.

To distribute:
1. Set your Team in Signing & Capabilities.
2. Archive: **Product → Archive**.
3. Notarize via Xcode Organizer or `xcrun notarytool`.
4. Export as a **Developer ID** signed `.app`, wrap in a `.dmg`.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| FN key does nothing | Grant **Input Monitoring** and relaunch |
| Text not inserted | Grant **Accessibility** and relaunch; if still failing, Cmd-V fallback should activate automatically |
| "Model not loaded" in menu | Wait for download to complete or check internet connection |
| No audio captured | Grant **Microphone** in System Settings → Privacy |
| App not in menu bar | Check Activity Monitor — it may be running without a status item (rare build issue; rebuild clean) |
