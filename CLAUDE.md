# Shhhcribble — project context for Claude

This file is the single source of truth for "what Claude should know before touching this repo." Skim it at the start of every session.

---

## What this app is

A menu-bar-only macOS voice-to-text utility. Hold the hotkey → speak → release → transcribed text pastes into the focused field. Runs entirely on-device via [FluidAudio](https://github.com/FluidInference/FluidAudio) + NVIDIA Parakeet V3 (CoreML). No cloud, no API keys.

**Target OS:** macOS 14+ (tested on 26 Tahoe). **Xcode:** 15+. **Language:** Swift.

---

## Directory map

```
Shhhcribble/
├── App/
│   ├── main.swift                ← NSApplicationMain bootstrap
│   └── AppDelegate.swift         ← Owns all subsystems; recording state machine
├── Audio/
│   └── AudioRecorder.swift       ← AVAudioEngine lifecycle — FRAGILE, read class doc before editing
├── HotKey/
│   └── HotKeyMonitor.swift       ← Carbon RegisterEventHotKey (no Input Monitoring needed)
├── Transcription/
│   ├── TranscriptionEngine.swift ← FluidAudio AsrManager wrapper
│   ├── ModelManager.swift        ← Static registry: models, hotkeys, prefs, history
│   └── FillerWordFilter.swift    ← Regex strip of "um", "uh", etc.
├── TextInsertion/
│   └── TextInserter.swift        ← AX direct insert → Cmd+V fallback → clipboard fallback
├── UI/
│   ├── SoundwavePanel.swift      ← Floating NSPanel (nonactivating)
│   ├── SoundwaveView.swift       ← SwiftUI pill animation
│   ├── MenuBarController.swift   ← NSStatusItem + menu rebuilds
│   ├── SettingsView.swift        ← Settings form (SwiftUI)
│   └── SettingsWindowController.swift
└── Resources/
    ├── Info.plist                ← CFBundleShortVersionString is the single source of truth for the About string
    ├── Shhhcribble.entitlements
    ├── Assets.xcassets/
    ├── PrivacyInfo.xcprivacy
    └── shhhcribble-scribble-sound.mp3
```

`Distribution/` — packaging + diagnostics (see "Tooling" below).

---

## Load-bearing decisions (don't relitigate without reading why)

### AudioRecorder: fresh AVAudioEngine per recording
**Why:** v2.0's warm-engine optimization created route-handling edge cases (Bluetooth toggles, sleep/wake, Continuity Mic re-routing) that couldn't reliably be fixed by layering stale-state detectors. Fresh-per-recording trades 100-200 ms of cold-start latency for bulletproof hardware re-binding. See `AudioRecorder.swift` class doc.

### Voice processing is conditional on Bluetooth
**Why:** AirPods stay in A2DP (output-only) and the tap silently gets empty buffers unless we flip the input node to AUVoiceIO, which signals voice-capture intent to CoreAudio and triggers HFP activation. But AUVoiceIO's AGC + noise suppression is tuned for close-mic phone-call style — it suppresses normal dictation from a ~50 cm built-in MacBook mic. So: VP on for BT inputs, off for wired/built-in. Check runs on every `startEngine()` so mid-recording device swaps reconfigure.

### Carbon hotkeys (not CGEventTap)
**Why:** RegisterEventHotKey doesn't require Input Monitoring permission and is never auto-disabled by macOS. Downside: fixed list of key combos, no arbitrary chords. That's fine.

### Activation mode defaults to Toggle
**Why:** Push-to-talk was tiring for longer dictations; tap-to-start-tap-to-stop is lower-effort. Users can switch back in Settings.

### Snappy-close UX (v2.1.7) + honest no-result correction
On hotkey release, `endRecording()` fires the scribble sound AND jumps straight to "Copied!" — skipping the "Transcribing…" dots. Transcription still runs in the background; paste happens whenever it finishes. The optimism is still the right default (waiting for transcription before any confirmation felt sluggish), but the pill is now *corrected after the fact* when the result proves the optimism wrong: empty transcriptions downgrade to a neutral `.noResult` state ("No speech detected", muted `waveform.slash` icon, 1.6 s auto-hide) via `SoundwavePanel.showNoResult()`; caught transcription errors route to `showError("Transcription failed")`. Both re-present the panel if `showCopied`'s hide timer already fired. Copy was chosen to read as "we didn't hear you" rather than an error — deliberately distinct from the red `.error` state reserved for real failures (permission denied, no mic detected).

### About version reads from Info.plist
Single source of truth at release time. Bump `CFBundleShortVersionString` only; the About panel reflects it automatically.

### History persisted via UserDefaults, cap 10
Survives relaunch via JSON-encoded `[TranscriptionEntry]` under `"transcriptionHistory"`. Cap chosen for menu readability, not storage.

### Hidden picker labels in Settings
Section headers already name each setting; inline `Picker("Model", ...)` labels duplicated them visually. Every picker uses `.labelsHidden()`.

### Escape-to-cancel during recording
**Why:** users sometimes start a recording and want to bail without pasting. An `NSEvent` global keyDown monitor is installed only while `state == .recording` (see `AppDelegate.escapeMonitor`). On Escape it tears down the recording, skips transcription, and returns the panel to idle. Monitor is removed on state exit to avoid swallowing Escape elsewhere.

### Clipboard restore on any successful paste path
**Why:** we save the user's prior clipboard and restore it ~2 s after the transcription lands on both the `.accessibilityInserted` path (AX-insert synchronously committed) and the `.pastedViaKeyboard` path (Cmd+V via `postToPid`). The 2 s window gives the user time to visually confirm the paste and to manually ⌘V the transcription if the target app silently dropped the event (Electron hosts occasionally do). An `NSPasteboard.changeCount` guard prevents clobbering anything the user copied during the window. Only the `.copiedToClipboard` path (no targetPid / Finder) leaves the transcription on the clipboard indefinitely, since no auto-paste was attempted.


---

## Lessons learned (anti-patterns to avoid)

- **Never run a second `AudioRecorder` while the main one is idle.** Two engines sharing the voice-processing lifecycle deadlock the main thread on the `AVAudioEngineConfigurationChange` notification handler. Spindump confirmed: `AVAudioEngine dealloc → dispatch_sync_f_slow`. Broke the onboarding mic-test step; deleted it.
- **Don't bundle features into one big PR.** v2.2.0 merged onboarding + input picker + launch sound + launch-at-login + Escape-to-cancel + brand gradient in one branch. One feature (mic test) caused a system-wide keyboard lockup that took the whole thing down. Since then: one feature per branch, build + verify in isolation, merge incrementally.
- **Don't touch `AudioRecorder` unless you have to.** v2 spent weeks stabilising this file. Device pinning, custom tap formats, lifecycle changes — all high-risk.
- **Log before you chase.** `Distribution/collect-logs.sh` caught the spindump that diagnosed the hang. Running it *during* a reproduction is the fastest path to a root cause.
- **Fresh Xcode builds invalidate Accessibility grants.** Every clean build produces a new binary signature. TCC sees it as a different app. If auto-paste "stops working" after a rebuild, first step: remove Shhhcribble from System Settings → Privacy → Accessibility and re-add it.

---

## Pref keys (UserDefaults, domain `com.shhhcribble.app`)

| Key | Type | Default | What it does |
|---|---|---|---|
| `selectedParakeetModel` | String | `"parakeet-v3"` | Which FluidAudio model variant to load |
| `selectedHotkeyID` | String | `"optSpace"` | Which preset hotkey is active |
| `activationMode` | String | `"toggle"` | `"pushToTalk"` or `"toggle"` |
| `fillerFilterEnabled` | Bool | `true` | Strip um/uh/hmm before pasting |
| `transcriptionHistory` | Data (JSON) | `[]` | Last 10 transcriptions |

---

## Release workflow

1. Bump `CFBundleShortVersionString` in `Shhhcribble/Resources/Info.plist` (semver major.minor.patch).
2. Bump `CFBundleVersion` (monotonic integer).
3. Update README "What's new" if user-facing changes.
4. Verify with `xcodebuild -scheme Shhhcribble -configuration Debug build`.
5. Smoke test in Xcode (⌘R): record → paste, AirPods still work, Settings renders.
6. `bash Distribution/create-dmg.sh` → `~/Desktop/Shhhcribble.dmg`.
7. Commit: `Bump version to X.Y.Z`.
8. Tag: `git tag vX.Y.Z-stable`.
9. Push tag only when ready for external distribution.

---

## Tooling

- **`Distribution/create-dmg.sh`** — builds Release + ad-hoc signs + packages drag-to-Applications DMG on the desktop.
- **`Distribution/set-dmg-layout.py`** — called by create-dmg.sh to position the app icon and Applications alias in the DMG window.
- **`Distribution/collect-logs.sh`** — diagnostic bundler. Call with `--keep N` to cap retained bundles (default 5), `--prune` to clean up without collecting.

Logs land in `~/shhhcribble-logs/<YYYYMMDD-HHMMSS>/`.

---

## Branches

- **`shhhcribble/v2`** — canonical production line (remote). Every shipped version tagged as `vX.Y.Z-stable`.
- **`claude/v2-plus-onboarding`** — current working branch. Based on v2.1.8 + incremental additions.
- **`backup/pre-revert-2.2.0`** — local snapshot of the failed v2.2.0 experiment (onboarding + input picker + launch sound bundled). Kept for cherry-picking individual features back one-by-one.

Avoid pushing work-in-progress branches to `origin` without explicit approval.

---

## When adding a feature

1. Branch off `shhhcribble/v2` (not off `claude/v2-plus-onboarding` unless the new feature genuinely depends on something already there).
2. Keep scope small — one feature per branch.
3. Build + verify + smoke-test before committing anything else on top.
4. Update CLAUDE.md when the change introduces a new load-bearing decision or pref key.
5. Run `collect-logs.sh` if anything audio-related misbehaves during verification.
