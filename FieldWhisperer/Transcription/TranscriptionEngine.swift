import Foundation
import WhisperKit

/// Wraps WhisperKit to provide async transcription.
/// Models are downloaded from HuggingFace on first use and cached in
/// ~/Library/Caches/huggingface/hub/  (subsequent launches load instantly).
@MainActor
final class TranscriptionEngine: ObservableObject {

    // MARK: - State

    enum LoadingState: Equatable {
        case unloaded
        case loading
        case ready
        case failed(String)

        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.unloaded, .unloaded), (.loading, .loading), (.ready, .ready): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var loadingState: LoadingState = .unloaded
    @Published var currentModelName: String = ModelManager.selectedModel

    private var whisperKit: WhisperKit?

    var isReady: Bool {
        if case .ready = loadingState { return true }
        return false
    }

    var statusText: String {
        switch loadingState {
        case .unloaded:        return "Model not loaded"
        case .loading:         return "Loading \(modelDisplayName(currentModelName))…"
        case .ready:           return "Ready · \(modelDisplayName(currentModelName))"
        case .failed(let err): return "Error: \(err)"
        }
    }

    // MARK: - Model loading

    func loadModel(variant: String) async {
        currentModelName = variant
        loadingState = .loading
        print("[FieldWhisperer] Loading model: \(modelDisplayName(variant)) (\(variant))…")

        do {
            // WhisperKit automatically downloads the model if not cached
            // and loads the CoreML optimized variant for the current device.
            let config = WhisperKitConfig(
                model: variant,
                verbose: true,
                logLevel: .debug,
                prewarm: false,
                load: true,
                download: true
            )
            whisperKit = try await WhisperKit(config)
            loadingState = .ready
            print("[FieldWhisperer] ✅ Model loaded successfully: \(variant)")
        } catch {
            let msg = error.localizedDescription
            loadingState = .failed(msg)
            print("[FieldWhisperer] ❌ Model loading failed: \(msg)")
        }
    }

    func reloadModel(variant: String) async {
        whisperKit = nil
        loadingState = .unloaded
        await loadModel(variant: variant)
    }

    // MARK: - Transcription

    func transcribe(audioSamples: [Float]) async throws -> String {
        guard let wk = whisperKit else {
            throw TranscriptionError.notLoaded
        }
        // Minimum ~0.5 s of audio to avoid spurious transcriptions
        let minSamples = Int(targetSampleRate * 0.5)
        guard audioSamples.count > minSamples else {
            print("[FieldWhisperer] Audio too short (\(audioSamples.count) samples, need >\(minSamples)). Skipping.")
            return ""
        }

        print("[FieldWhisperer] Transcribing \(audioSamples.count) samples " +
              "(~\(String(format: "%.1f", Double(audioSamples.count) / targetSampleRate))s of audio)…")

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: nil,              // auto-detect
            temperature: 0.0,
            temperatureFallbackCount: 3,
            sampleLength: 224,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = try await wk.transcribe(audioArray: audioSamples, decodeOptions: options)
        let text = results.compactMap { $0.text }.joined(separator: " ")
        print("[FieldWhisperer] Transcription result: \"\(text)\"")
        return text
    }

    // MARK: - Helpers

    private let targetSampleRate: Double = 16_000

    private func modelDisplayName(_ id: String) -> String {
        ModelManager.availableModels.first(where: { $0.id == id })?.displayName ?? id
    }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        "Whisper model is not loaded yet. Please wait for the model to finish loading."
    }
}
