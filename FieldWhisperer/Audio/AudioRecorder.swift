import AVFoundation

/// Captures microphone input and converts it to 16 kHz mono Float32 samples
/// required by WhisperKit. A level callback is fired on the main thread with
/// a normalized amplitude (0–1) for the soundwave UI.
///
/// Thread-safety note: All public methods must be called on the main thread.
/// The AVCaptureDevice.requestAccess callback is async; `levelCallback` being
/// non-nil is used as a cancellation signal — if stop() clears it before the
/// callback fires, startEngine() is never called, preventing double-tap crashes.
final class AudioRecorder {

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private var levelCallback: ((Float) -> Void)?
    private var tapInstalled = false

    // WhisperKit requires 16 kHz mono Float32
    private let targetSampleRate: Double = 16_000
    private let targetFormat: AVAudioFormat

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
    }

    // MARK: - Public API

    /// Start recording. `levelCallback` is called on the main thread with
    /// a 0–1 amplitude suitable for driving the soundwave animation.
    func start(levelCallback: @escaping (Float) -> Void) {
        // Clean up any previous session that didn't shut down fully
        // (guards against the race condition where the permission callback
        // fired after a previous stop(), leaving the engine running)
        tearDown()

        self.levelCallback = levelCallback
        samples.removeAll(keepingCapacity: true)

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard granted else {
                print("[FieldWhisperer] Microphone permission denied.")
                return
            }
            DispatchQueue.main.async {
                // If stop() was called while we awaited permission, levelCallback
                // will be nil — abort silently instead of starting a phantom session.
                guard let self, self.levelCallback != nil else { return }
                self.startEngine()
            }
        }
    }

    /// Stop recording and return the captured samples.
    func stop() -> [Float] {
        let captured = samples
        tearDown()
        return captured
    }

    /// Non-destructive snapshot of samples captured so far (for live transcription).
    var currentSamples: [Float] { samples }

    // MARK: - Private

    private func tearDown() {
        // Setting levelCallback = nil before removeTap / stop acts as a
        // cancellation flag for any in-flight permission callbacks.
        levelCallback = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
            engine.reset()  // releases CoreAudio unit graph; lets macOS restore device defaults
        }
        samples.removeAll(keepingCapacity: true)
    }

    private func startEngine() {
        // Guard against double-tap (should not happen, but be defensive)
        guard !tapInstalled else { return }

        let inputNode   = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("[FieldWhisperer] Could not create AVAudioConverter.")
            return
        }

        tapInstalled = true
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = self.targetSampleRate / inputFormat.sampleRate
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard let output = AVAudioPCMBuffer(pcmFormat: self.targetFormat,
                                                frameCapacity: outFrames) else { return }

            var inputConsumed = false
            var convError: NSError?
            converter.convert(to: output, error: &convError) { _, outStatus in
                if inputConsumed { outStatus.pointee = .noDataNow; return nil }
                outStatus.pointee = .haveData
                inputConsumed = true
                return buffer
            }

            guard convError == nil,
                  let channelData = output.floatChannelData?[0] else { return }

            let frameCount = Int(output.frameLength)
            let chunk = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(max(frameCount, 1)))
            let level = min(rms * 20.0, 1.0)

            DispatchQueue.main.async {
                self.samples.append(contentsOf: chunk)
                self.levelCallback?(level)
            }
        }

        do {
            try engine.start()
        } catch {
            tapInstalled = false
            print("[FieldWhisperer] AVAudioEngine start failed: \(error.localizedDescription)")
        }
    }
}
