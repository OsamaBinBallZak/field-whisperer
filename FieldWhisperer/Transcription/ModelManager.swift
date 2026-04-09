import Foundation

/// Central registry for available Whisper model variants and the user's preference.
enum ModelManager {

    struct ModelInfo {
        let id: String          // WhisperKit model identifier
        let displayName: String // Shown in Settings UI
    }

    static let availableModels: [ModelInfo] = [
        ModelInfo(id: "openai_whisper-tiny",   displayName: "Tiny   (~40 MB) – Fastest"),
        ModelInfo(id: "openai_whisper-base",   displayName: "Base   (~75 MB) – Fast"),
        ModelInfo(id: "openai_whisper-small",  displayName: "Small  (~140 MB) – Balanced ✦"),
        ModelInfo(id: "openai_whisper-medium", displayName: "Medium (~450 MB) – Accurate"),
    ]

    private static let key = "selectedWhisperModel"
    private static let defaultModel = "openai_whisper-small"

    static var selectedModel: String {
        get { UserDefaults.standard.string(forKey: key) ?? defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
