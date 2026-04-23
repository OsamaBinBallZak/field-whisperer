# Shhhcribble

A native macOS voice-to-text utility.  
Hold **⌥Space** to record, release to transcribe — text is automatically pasted into the focused app.

Powered by [NVIDIA Parakeet V3](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml) via [FluidAudio](https://github.com/FluidInference/FluidAudio). Runs entirely on-device — no API keys, no cloud.

---

## Features

- **⌥Space push-to-talk** — global hotkey, works in any app, no Input Monitoring required
- **Toggle mode** — tap to start, tap to stop (great for long recordings)
- **Auto-paste** — text goes directly into the focused field (native apps via Accessibility, everything else via ⌘V, clipboard as fallback)
- **Clipboard restore** — your prior clipboard is restored ~2 s after paste, so transcribing doesn't clobber the URL / code snippet you had copied
- **Escape-to-cancel** — press Escape mid-recording to abort without pasting
- **Parakeet V3** — ~10× faster than Whisper, better accuracy, no silence hallucination, 25 languages
- **Floating soundwave panel** — recording state, live transcription preview, "Copied!" / "No speech detected" feedback
- **Transcription history** — last 10 transcriptions accessible from the menu bar, persist across launches
- **Menu bar only** — no Dock icon
- **Filler word filter** — optionally strips "um", "uh", "hmm" from transcriptions

---

## Install

### From DMG

Download the latest `Shhhcribble.dmg` from the [Releases page](https://github.com/itsHendri/Shhcribble/releases).

1. Open the `.dmg`, drag **Shhhcribble** to **Applications**
2. **Right-click → Open** on first launch (bypasses Gatekeeper — only needed once)
3. Grant **Microphone** when prompted
4. Wait for the model to download (~494 MB, one-time)

> If right-click → Open doesn't work, run `xattr -cr /Applications/Shhhcribble.app` in Terminal.

### Build from source

```bash
git clone https://github.com/itsHendri/Shhcribble.git shhhcribble
cd shhhcribble
open Shhhcribble.xcodeproj
```

1. Select the **Shhhcribble** scheme and your Mac as destination
2. **Signing & Capabilities → Team** — pick your Apple Developer team
3. **⌘R** to build and run

Requires **macOS 14.0+** and **Xcode 15.0+**.

---

## Usage

1. Click into any text field
2. **Hold ⌥Space** — soundwave panel appears
3. Speak
4. **Release ⌥Space** — text is transcribed and pasted

> **Toggle mode:** In Settings → Activation, switch to toggle mode. Tap ⌥Space to start, tap again to stop.

---

## Settings

Click the menu bar icon → **Settings…**

| Setting | Options |
|---|---|
| **Model** | Parakeet V3 (multilingual, 25 langs) ✦ / Parakeet V2 (English-optimized) |
| **Activation** | Push-to-talk (hold) / Toggle (tap) |
| **Hotkey** | ⌥Space, ⌃Space, ⌥`, ⌃⌥Space |
| **Filler filter** | On/Off — removes um, uh, hmm |

---

## Permissions

| Permission | Required? | Why |
|---|---|---|
| **Microphone** | Yes | Prompted automatically |
| **Accessibility** | Optional | Enables direct text insertion and Escape-to-cancel; without it, text goes via ⌘V and Escape does nothing |

> After rebuilding in Xcode, re-grant Accessibility: remove Shhhcribble from the list, then re-add it. AX is tied to the binary signature, which changes on every clean build.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| ⌥Space does nothing | Model still loading — wait for "Ready" in menu bar |
| Text not pasted | Grant Accessibility in System Settings → Privacy |
| "No microphone detected" | Connect a mic and check System Settings → Sound → Input |
| App not in menu bar | Check Activity Monitor; rebuild clean (⌘⇧K then ⌘R) |

---

## Distribution

Build a shareable DMG:

```bash
bash Distribution/create-dmg.sh
```

Produces **Shhhcribble.dmg** on your Desktop. Recipients right-click → Open on first launch.

---

*Built by [Hendri](https://github.com/itsHendri). Uses [FluidAudio](https://github.com/FluidInference/FluidAudio) and NVIDIA Parakeet V3 for on-device transcription.*
