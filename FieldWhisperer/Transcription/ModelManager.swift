import Foundation
import Carbon.HIToolbox

/// Central registry for available Whisper model variants and hotkey options.
enum ModelManager {

    // MARK: - Whisper models

    struct ModelInfo {
        let id: String
        let displayName: String
    }

    static let availableModels: [ModelInfo] = [
        ModelInfo(id: "openai_whisper-tiny",   displayName: "Tiny   (~40 MB) – Fastest"),
        ModelInfo(id: "openai_whisper-base",   displayName: "Base   (~75 MB) – Fast"),
        ModelInfo(id: "openai_whisper-small",  displayName: "Small  (~140 MB) – Balanced ✦"),
        ModelInfo(id: "openai_whisper-medium", displayName: "Medium (~450 MB) – Accurate"),
    ]

    private static let modelKey    = "selectedWhisperModel"
    private static let defaultModel = "openai_whisper-small"

    static var selectedModel: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    // MARK: - Hotkey presets

    struct HotkeyOption: Identifiable {
        let id:        String    // stable key for UserDefaults
        let label:     String    // shown in Settings UI (full description)
        let symbol:    String    // short symbol for menu hint
        let keyCode:   UInt32
        let modifiers: UInt32
    }

    static let availableHotkeys: [HotkeyOption] = [
        HotkeyOption(id: "optSpace",  label: "⌥Space  (Option+Space)",    symbol: "⌥Space",  keyCode: UInt32(kVK_Space),      modifiers: UInt32(optionKey)),
        HotkeyOption(id: "ctrlSpace", label: "⌃Space  (Control+Space)",   symbol: "⌃Space",  keyCode: UInt32(kVK_Space),      modifiers: UInt32(controlKey)),
        HotkeyOption(id: "optGrave",  label: "⌥`       (Option+Backtick)", symbol: "⌥`",      keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(optionKey)),
        HotkeyOption(id: "ctrlOpt",   label: "⌃⌥Space (Ctrl+Opt+Space)",  symbol: "⌃⌥Space", keyCode: UInt32(kVK_Space),      modifiers: UInt32(controlKey | optionKey)),
    ]

    private static let hotkeyKey     = "selectedHotkeyID"
    private static let defaultHotkey = "optSpace"

    static var selectedHotkeyID: String {
        get { UserDefaults.standard.string(forKey: hotkeyKey) ?? defaultHotkey }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyKey) }
    }

    static var selectedHotkey: HotkeyOption {
        availableHotkeys.first(where: { $0.id == selectedHotkeyID }) ?? availableHotkeys[0]
    }

    // MARK: - Feature flags

    /// Default true — strip um/uh/hmm/er and parenthetical fillers before pasting.
    static var fillerFilterEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: "fillerFilterEnabled") != nil else { return true }
            return UserDefaults.standard.bool(forKey: "fillerFilterEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "fillerFilterEnabled") }
    }

    /// Default true — play a soft sound when recording starts and stops.
    static var soundFeedbackEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: "soundFeedbackEnabled") != nil else { return true }
            return UserDefaults.standard.bool(forKey: "soundFeedbackEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "soundFeedbackEnabled") }
    }

    // MARK: - Transcription history

    struct TranscriptionEntry {
        let text: String
        let date: Date

        /// Truncated title for display in menus (max 60 chars).
        var menuTitle: String {
            let prefix = String(text.prefix(60))
            return text.count > 60 ? "\(prefix)…" : prefix
        }
    }

    private(set) static var history: [TranscriptionEntry] = []

    static func addToHistory(_ text: String) {
        history.insert(TranscriptionEntry(text: text, date: Date()), at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
    }

    static func clearHistory() {
        history.removeAll()
    }
}
