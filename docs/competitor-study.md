# Superwhisper competitor study — what to steal for Shhhcribble

Source: static analysis of `/Applications/superwhisper.app` v2.12.1 on 2026-04-22.
No runtime tracing in this pass — Part A2 of the research plan (log stream, sample, lsof) was skipped; the static surface gave enough signal to act on.

---

## Side-by-side

| Dimension | Shhhcribble (v2.1.8) | Superwhisper (v2.12.1) |
|---|---|---|
| ASR model | Parakeet V3 via FluidAudio `AsrManager` | **Same Parakeet family** — they ship `argmaxinc/parakeetkit-pro` (Argmax's Parakeet wrapper), plus WhisperKit models as alternatives |
| Transcription mode | **Batch**: accumulate full buffer, transcribe on stop. Live mode runs every 3 s on growing buffer but shows as a separate UI. | **Streaming**: `Argmax.LiveTranscriberStreamSession` + `AudioChunking` protocol — audio is chunked and transcribed continuously with partial results |
| Audio capture | Fresh `AVAudioEngine` per recording (v2.1.8 load-bearing decision). Follows system default input. VP conditional on Bluetooth. | `AVAudioEngine` with `installTapOnBus`/`removeTapOnBus`. **Input device pinned** (`useDefaultAudioDevice = 0`, explicit `selectedDeviceID`). Tracks usage counts (`deviceSelectionCounts`) to rank picker. |
| VAD / silence | None. Whole buffer goes to Parakeet. | **On-device VAD + segmentation + speaker embedding** — ships `vad-v1.onnx`, `seg-v1.onnx`, `emb-v1.onnx` in Application Support. Likely trims silence + early cutoff. |
| Hotkey | Carbon `RegisterEventHotKey` | Carbon `RegisterEventHotKey` via a `CarbonKeyboardShortcuts.swift` abstraction. **Same technique.** |
| Paste | AX direct insert → Cmd+V fallback → clipboard. **Clobbers the user's clipboard permanently.** Electron denylist (new). | `pasteText:restorePasteboard:restoreInterval:completionHandler:` — they **save the user's prior clipboard, paste, then restore it after an interval**. |
| App-aware output | None. Same text inserted everywhere. | `bundled_app_info.json` maps known apps to `text_input_format`: `"url"` for Chrome/Firefox, `"code"` for VS Code, `"chat_message"` for Slack/Teams/Zoom, `"rich_text"` for Notion/Photoshop. Output is tailored to destination. |
| Sounds at launch | Single 0.5 s MP3 via NSSound | 10.5 s `Intro.m4a` (probably onboarding, not every launch) + 16 s `Loop.m4a` (sustained during recording) |
| Sounds per recording | Single scribble MP3, played on hotkey release | **4 variants** of Start*, Stop*, noResult* (~1.1 s each), plus `PreStop.m4a` and `PreStop_fast.m4a` for anticipatory cues before stopping |
| Empty-result UX | Shows optimistic "Copied!" even for empty transcriptions (v2.1.7 snappy-close decision) | Dedicated `noResult1-4.m4a` sound set — explicit feedback when transcription is empty |
| Auto-update | None — manual DMG | Sparkle feed at `https://superwhisper.com/appcast.xml` |
| Binary | arm64 native | **Universal** (arm64 + x86_64) — no performance ding from Rosetta on Apple Silicon despite what otool's first-arch output suggested |
| History store | `UserDefaults` JSON, cap 10 | SQLite (`superwhisper.sqlite` via GRDB framework), unbounded — plus chunked audio retention |
| LLM post-processing | None | Bundled `libllama` + jinja templates for `gpt-oss`, `llama-3.2`, `deepseek-r1`, `mistral`, `phi-2`, `ministral` — optional "rewrite my rambling" step after transcription |
| LLM prompt constraints (visible in binary) | — | `"Don't replace partial matches: 'John' should not become '@JohnC12345'"` — they explicitly prompt against over-eager autocomplete from LLMs |
| Crash reporting | None | Sentry.framework linked |
| Entitlements | `audio-input`, `apple-events`, `accessibility` | `audio-input`, `apple-events` only — they do paste without declared Accessibility entitlement (uses AXIsProcessTrusted prompt flow) |
| Bundle size | ~20 MB (our build) | Much larger — ships llama.cpp + ggml-metal + onnxruntime + Whisper models + Parakeet |

### Evidence citations (binary strings)

- `/Users/ultra/Development/superwhisper/superwhisper/superwhisper/Managers/PasteboardManager.swift` — leaked developer build path (their module is `PasteboardManager` + `STKPasteboardManager`)
- `pasteText:restorePasteboard:restoreInterval:completionHandler:` — clipboard-restore paste signature
- `VoiceProcessor::processAudioChunked`, `AudioBuffer::processInChunks`, `ThreadPool::parallelFor` — chunked parallel pipeline in C++
- `$s10WhisperKit13AudioChunkingP`, `$s6Argmax28LiveTranscriberStreamSessionP` — streaming transcriber API
- `Received HID event with unknown KeyCode` — raw HID consumption (possibly for chord / modifier detection beyond hotkey)

---

## Top recommendations (ranked by impact / hour)

### 1. **Restore-pasteboard strategy** — tiny cost, high delight

We currently call `NSPasteboard.clearContents()` then `setString(text)`, which obliterates whatever the user had copied. Superwhisper saves the prior pasteboard items, writes the transcription, simulates Cmd+V, then **after a short interval restores the original contents**. The user's clipboard history is preserved.

- **Where**: [TextInserter.swift:22-25](../Shhhcribble/TextInsertion/TextInserter.swift:22)
- **Shape**: snapshot `pasteboard.pasteboardItems` before writing; after paste (AX success OR Cmd+V posted), `asyncAfter` 150–300 ms, clear and re-write the original items.
- **Cost**: ~30 LOC in `TextInserter`. Needs a care path for Finder/clipboard-only fallback (don't restore — user might need to ⌘V the transcription themselves).
- **CLAUDE.md impact**: add a note to the TextInserter comment describing the restore.

### 2. **"noResult" sound + honest empty-transcription UI** — small cost, high UX honesty

Our v2.1.7 "snappy-close" trade-off shows "Copied!" optimistically even when the transcription is empty. Superwhisper ships explicit `noResult` sounds — they own the failure case. Two options:

- **Minimal**: play a distinct sound (we don't need 4 variants; one low "nope" tone is fine) and flip the pill state from `.copied` to `.empty` with copy `"No speech detected"`.
- **Full**: also suppress the clipboard write, so the user's prior clipboard isn't clobbered by an empty string (overlaps with recommendation 1).

- **Where**: [AppDelegate.swift:228-229](../Shhhcribble/App/AppDelegate.swift:228), [SoundwavePanel.swift:97-113](../Shhhcribble/UI/SoundwavePanel.swift:97)
- **Cost**: ~40 LOC + one sound asset. Revisits the v2.1.7 "snappy-close" decision in CLAUDE.md.

### 3. **Pin input device + Settings picker** — small cost, addresses real bug

`defaults read com.superduper.superwhisper` shows `useDefaultAudioDevice = 0` and `selectedDeviceID = BuiltInMicrophoneDevice`. They pin. We follow system default, which is why yesterday's logs showed aggregate-device churn and the "iOS mic pop" from Continuity-mic presence.

- **Where**: `AudioRecorder.swift` (device selection path), Settings picker in `SettingsView.swift`
- **Shape**: a new `selectedInputDeviceUID` pref (default empty = follow system); if set, use `kAudioHardwarePropertyDeviceForUID` to resolve and set on the input node. UI picker lists `NSInputDevice` equivalents (iterate `kAudioHardwarePropertyDevices`).
- **Cost**: medium — device enumeration is CoreAudio boilerplate. ~150 LOC.
- **CLAUDE.md impact**: document the pref and explain why pinning helps (Continuity-mic churn, aggregate-device init clicks).

### 4. **Partial / streaming transcription** — medium cost, first-word latency win

Superwhisper uses `Argmax.LiveTranscriberStreamSession` with chunked audio. We call `AsrManager.transcribe(buffer)` on the full accumulated buffer after stop. Our "live transcription" task runs every 3 s on the growing buffer, but that's batch-in-a-loop, not true streaming.

- **Research needed** before building: does FluidAudio expose a streaming/partial API? If yes, switch. If no, consider adopting **WhisperKit via Argmax SDK** for streaming — same Parakeet model family, different harness.
- **Cost**: medium-to-large. Could be a 1–2 day spike. High payoff — first word appears while you're still talking.
- **CLAUDE.md impact**: introduces a new subsystem; revisits the "load full buffer on stop" contract.

### 5. **Warmed engine with route-change invalidation** — medium cost, high risk

Our v2.1.8 "fresh AVAudioEngine per recording" was adopted because warm engines had route-handling bugs (Bluetooth toggle, sleep/wake, Continuity Mic re-routing). Superwhisper keeps the engine warm across recordings — that's some of the "snappier start" feel.

- **Don't revisit this yet**. First do 1–3, then measure remaining latency. If cold-start is still the bottleneck, attempt a warmed-engine variant with **explicit teardown on `AVAudioEngineConfigurationChange` notifications** rather than time-based staleness.
- **Cost**: high — this is the same territory that cost weeks in v2. Do NOT combine with other feature work per CLAUDE.md "one feature per branch".

### 6. **App-aware output format** (defer)

The `bundled_app_info.json` idea — Chrome gets a URL, VS Code gets code, Slack gets a chat message — is interesting but arguably LLM-dependent. They almost certainly run transcription output through their bundled llama.cpp with an app-specific prompt template. That's a different product category for us. **Defer.**

### 7. **Sparkle auto-update** (defer)

Worth doing eventually, but doesn't affect latency/UX of the core loop. Separate concern, separate branch.

---

## Suggested spike branches (one feature each, per CLAUDE.md)

1. `shhhcribble/v2-pasteboard-restore` — recommendation 1
2. `shhhcribble/v2-empty-result-ux` — recommendation 2
3. `shhhcribble/v2-pin-input-device` — recommendation 3

Do them in that order. Each is small and shippable on its own; together they address the biggest gaps the static analysis surfaced without the risk of a warmed-engine rewrite.

---

## Runtime observation (not yet done)

When worth doing, have Superwhisper running and run these from a terminal:

- `log stream --process superwhisper --level debug --style syslog` in one pane; trigger a recording; note their phase markers and timestamps.
- `lsof -p $(pgrep superwhisper)` while **idle** vs **recording** — diff the audio-device descriptors to confirm whether they hold the mic open between recordings (warmed engine hypothesis).
- `sample $(pgrep superwhisper) 5` while idle — does anything in their thread list indicate a hot AVAudioEngine thread (QuIO_InputGenerator)?

If the warmed-engine hypothesis holds, recommendation 5 graduates from "defer" to "validate and prototype".

---

## Cross-competitor patterns (merged with Claude Chat research, 2026-04-22)

A parallel audit covered MacWhisper, Whispering, VoiceInk, Aiko, WhisperKit/WhisperAX, and the whisper.cpp stream demo. Highlights that change or confirm our Superwhisper-only view:

### Confirms my findings

- **Superwhisper is largely batch**. The `LiveTranscriberStreamSession` symbol I found is likely used for their live-waveform preview, not the displayed output. Text appears as a block after key release.
- **Superwhisper keeps the model warm** via CoreML `.mlmodelc` cached ANE graph — same pattern our FluidAudio uses (logs show `Compiled model Preprocessor.mlmodelc in 10 ms`). Not a differentiator.
- **AirPods cause a 1–2 s stall** on Superwhisper too. They don't have a magic fix; they use a fresh engine and eat the cost.

### Corrects my findings

- Claude Chat says Superwhisper uses **CGEventTap** for hotkeys. The binary strings I pulled showed `CarbonKeyboardShortcuts.swift` + `RegisterEventHotKey`. **My read is more authoritative** — the Swift file path leaked from their build. They use Carbon (same as us).
- Claude Chat lists Superwhisper as Whisper-only CoreML. Static analysis showed **they also ship `argmaxinc/parakeetkit-pro`** in Application Support — they support Parakeet too.

### Net-new patterns worth learning

From the broader audit, the three highest-leverage patterns — none of which I had from static analysis alone:

**A. Persistent AVAudioEngine + debounced `AVAudioEngineConfigurationChangeNotification` handler** (VoiceInk, WhisperKit, most serious tools)

The canonical fix for the exact problems v2.0 → v2.1 tried to solve by going fresh-per-recording. Key detail Claude Chat surfaces: **AirPods fire 2–3 configuration-change notifications in rapid succession** during codec renegotiation. Without a ~300 ms debounce, naive handlers double-restart and deadlock. VoiceInk's changelog apparently shows them iterating on this for weeks. If we revisit warm engine, this is the spec.

**B. Two-phase model load: tiny at launch → large in background** (Voicey, referenced by Argmax)

Load a tiny model synchronously (<100 ms) so recordings are accepted immediately; swap to large-v3-turbo / Parakeet-V3 in the background after ~5 s. For us this is a smaller win — Parakeet V3 already loads in ~100 ms per our logs — but it eliminates any "app just launched, can't record yet" window.

**C. Eager streaming with redundant-prediction token confirmation** (WhisperKit, whisper.cpp `stream.cpp`)

The actual pattern for first-word-during-speech:
- Persistent AVAudioEngine tap → 16 kHz mono ring buffer.
- Every `step_ms` (typically 500 ms), run inference on a sliding window that keeps a `pcmf32_old` overlap (prevents sentence-boundary artifacts).
- Emit a token only when two consecutive inference passes agree on it.
- `EnergyVAD` (1 kHz high-pass + energy threshold) gates silence so we don't re-run on empty audio.

WhisperKit exposes this as **Eager Streaming Mode** — a config flag, not a rewrite. Argmax also ships **`ParakeetKit`** which pairs with our current model.

**D. Clipboard restore** (confirmed from my Superwhisper analysis)

Save prior pasteboard items, write transcription, paste, restore after 100–300 ms. MacWhisper sidesteps paste entirely (user copies manually) which is arguably snappier-feeling because there's zero paste-latency anxiety — worth noting as a fallback UX if ours gets flaky.

**E. VoiceInk Power Mode** (per-app context profiles)

On `NSWorkspace.didActivateApplicationNotification`, read the focused app's URL/title via AXUIElement and switch transcription profile. Aligns with Superwhisper's `bundled_app_info.json`. **Defer** for us — this only matters once we have LLM post-processing.

### Updated ranking with cross-competitor input

Revised from the original 7-item list:

| # | Change | Cost | Latency impact | Risk |
|---|---|---|---|---|
| 1 | Clipboard restore | 1–2 h | none (UX) | none |
| 2 | `noResult` sound + honest empty state | 2–3 h | none (UX) | none |
| 3 | Pin input device + Settings picker | ~1 d | fixes mic-pop bug | low |
| 4 | Two-phase model load (tiny → Parakeet V3) | ~1 d | removes ~100 ms launch-to-ready window | low |
| 5 | Persistent engine + debounced route-change handler | 2–3 d | saves ~100–200 ms per recording | **high** — same territory as v2 weeks-long stabilisation |
| 6 | Streaming transcription via ParakeetKit (Argmax) or switch engine | 3–5 d | first word appears mid-speech | medium — new dep |
| 7 | Power Mode / per-app profiles | 1–2 d | none (UX) | low — but needs LLM backend to shine |

### Stack question raised by the cross-audit

Claude Chat frames the choice as **Swift + WhisperKit** vs **Tauri + whisper.cpp subprocess**. We're Swift + FluidAudio today. The honest third option is **Swift + Argmax's SDK** (WhisperKit for English-Whisper-style + ParakeetKit for our current Parakeet). Swapping FluidAudio → ParakeetKit would:

- Keep the same model family (no accuracy regression).
- Give us access to `LiveTranscriberStreamSession` — which Superwhisper already bundles.
- Tie us to an SDK with a commercial license gate on higher-tier features.

A strict read: we should **evaluate whether FluidAudio's `AsrManager` exposes any streaming/partial API** before jumping to ParakeetKit. If FluidAudio's API is batch-only, ParakeetKit becomes a real contender for recommendation 6.

### Update (2026-04-22): FluidAudio already has streaming

Spot-check of the SwiftPM checkout at `DerivedData/.../SourcePackages/checkouts/FluidAudio/Sources/FluidAudio/`:

- `ASR/Parakeet/Streaming/StreamingAsrManager.swift` defines a `StreamingAsrManager` actor protocol with `appendAudio()`, `processBufferedAudio()`, `setPartialTranscriptCallback(_:)`, `getPartialTranscript()`, `finish()`, `reset()`.
- Three concrete impls: `StreamingEouAsrManager` (parakeet-EOU, 160 ms chunks, cache-aware), `StreamingNemotronAsrManager`, `SlidingWindowAsrManager` (TDT with overlapping windows).
- `VAD/VadManager+Streaming.swift` + `VadManager+SpeechSegmentation.swift` give us the VAD/EOU layer.
- `Shared/AudioStream.swift` + `Shared/AudioSourceFactory.swift` provide audio-stream plumbing.

**Conclusion**: no engine swap needed. Recommendation 6 (streaming) becomes a wiring job against an existing API, not a subsystem replacement. The streaming manager is an `Actor` with partial-result callbacks — the natural integration point is: feed the AVAudioEngine tap straight into `appendAudio()`, render `setPartialTranscriptCallback` output into the SoundwavePanel's `liveText`, call `finish()` on hotkey release.

This also unblocks the "warm engine" decision: streaming requires a persistent engine to append audio continuously. Warm-engine + streaming are the same feature, not two.

---

## Sequenced roadmap (updated)

Given the three decisions (top bottleneck = first-word latency; warm-engine with debounce; stay with FluidAudio), the right execution order is:

1. **`shhhcribble/v2-pasteboard-restore`** (recommendation 1) — tiny, ships first as a safety net while the bigger work is in flight.
2. **`shhhcribble/v2-pin-input-device`** (recommendation 3) — fixes yesterday's Continuity-mic pops; unblocks confident testing of the warm-engine work by removing a variable.
3. **`shhhcribble/v2-no-result-ux`** (recommendation 2) — tiny; ships in parallel with (2).
4. **`shhhcribble/v2-streaming`** (recommendations 5 + 6 combined, because they're the same change) — the big one. Replace fresh-per-recording + `AsrManager.transcribe(buffer)` with persistent `AVAudioEngine` feeding `StreamingEouAsrManager.appendAudio()` + partial-result callback → `liveText`. Subscribe to `AVAudioEngineConfigurationChangeNotification` with 300 ms debounce per the VoiceInk pattern. This is the feature the user actually wants — first word while still speaking.

(4) is where the weeks-long v2 territory risk lives. Mitigations baked in:

- Separate branch, off `shhhcribble/v2`, one feature (per CLAUDE.md).
- 300 ms debounce on the configuration-change handler (so AirPods' 2–3 rapid-fire notifications coalesce to one teardown).
- Keep `AsrManager.transcribe(buffer)` batch path behind a feature flag for rollback.
- Explicitly verify AirPods toggle, sleep/wake, Continuity Mic arrival/departure before merging.
- Collect a before/after logs bundle (`Distribution/collect-logs.sh`) for comparison.
