import SwiftUI

// MARK: - View model

enum RecordingUIState {
    case hidden
    case recording
    case transcribing
    case copied
}

@MainActor
final class SoundwaveViewModel: ObservableObject {
    @Published var state: RecordingUIState = .hidden
    @Published var audioLevel: Double = 0
    @Published var liveText: String = ""   // interim transcription shown while recording
    @Published var isVisible: Bool = false  // drives entry/exit animation
}

// MARK: - Typing view model

/// Appends characters one-at-a-time so live transcription feels like active
/// dictation rather than instant jumps to new text.
@MainActor
final class TypingViewModel: ObservableObject {
    @Published var displayedText: String = ""
    private var targetText: String = ""
    private var typingTask: Task<Void, Never>?

    func updateTarget(_ newText: String) {
        if newText.hasPrefix(displayedText) {
            // New text simply extends what's already displayed — continue typing
            targetText = newText
        } else {
            // Text changed (WhisperKit revised earlier words) — rewind to common prefix
            var commonLen = 0
            let dChars = Array(displayedText)
            let nChars = Array(newText)
            for i in 0..<min(dChars.count, nChars.count) {
                if dChars[i] == nChars[i] { commonLen = i + 1 } else { break }
            }
            displayedText = String(displayedText.prefix(commonLen))
            targetText = newText
        }

        typingTask?.cancel()
        typingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let current = self.displayedText
                let target  = self.targetText
                guard current.count < target.count else { break }
                let nextIdx = target.index(target.startIndex, offsetBy: current.count)
                self.displayedText = String(target[target.startIndex...nextIdx])
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }

    func reset() {
        typingTask?.cancel()
        typingTask = nil
        displayedText = ""
        targetText    = ""
    }
}

// MARK: - Root view

struct SoundwaveView: View {
    @ObservedObject var viewModel: SoundwaveViewModel

    var body: some View {
        // Outer transparent container (400×136) gives the spring animation room to
        // overshoot without being clipped by the NSPanel window boundary.
        ZStack {
            Color.clear

            // Inner animated pill — 320×56
            ZStack {
                // Frosted glass background: material blur + dark tint + hairline rim
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color(red: 0.02, green: 0.02, blue: 0.08).opacity(0.55))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )

                HStack(spacing: 0) {
                    // Mic / checkmark icon — always white, dot carries state colour
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(iconColor)
                        .padding(.leading, 16)
                        .padding(.trailing, 10)

                    switch viewModel.state {
                    case .recording:
                        // Bars always visible at fixed width
                        SoundwaveBars(audioLevel: viewModel.audioLevel)
                            .frame(width: 36)
                        // Single-line text types characters left→right as words arrive
                        ScrollingLiveText(text: viewModel.liveText)
                            .padding(.horizontal, 8)

                    case .transcribing:
                        HStack(spacing: 8) {
                            Text("Transcribing")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.55))
                            TranscribingDotsView()
                        }
                        Spacer()

                    case .copied:
                        Text("Copied! ⌘V to paste")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()

                    case .hidden:
                        SoundwaveBars(audioLevel: 0)
                            .frame(width: 36)
                        Spacer()
                    }

                    // Animated status dot — glows and pulses during recording
                    AnimatedDot(color: dotColor, animate: viewModel.state == .recording)
                        .padding(.leading, 2)
                        .padding(.trailing, 12)
                        .opacity(viewModel.state == .hidden ? 0 : 1)
                }
            }
            .frame(width: 320, height: 56)
            .clipShape(Capsule())
            // Shadow sits outside the clip so it renders on the whole capsule shape
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            // Entry / exit animation driven by isVisible
            .scaleEffect(viewModel.isVisible ? 1.0 : 0.78)
            .offset(y: viewModel.isVisible ? 0 : -18)
            .opacity(viewModel.isVisible ? 1.0 : 0.0)
        }
        .frame(width: 400, height: 136)
    }

    private var iconName: String {
        switch viewModel.state {
        case .copied: return "checkmark.circle.fill"
        default:      return "mic.fill"
        }
    }

    private var iconColor: Color {
        switch viewModel.state {
        case .copied: return .green
        default:      return .white.opacity(0.55)
        }
    }

    private var dotColor: Color {
        switch viewModel.state {
        case .recording:    return .red
        case .transcribing: return .orange
        case .copied:       return .green
        case .hidden:       return .clear
        }
    }
}

// MARK: - Animated status dot

/// A status dot with a radial-gradient core and a soft breathing halo when active.
struct AnimatedDot: View {
    let color: Color
    let animate: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            // Outer breathing halo
            Circle()
                .fill(color.opacity(pulse ? 0.28 : 0.0))
                .frame(width: 18, height: 18)
            // Core — radial gradient from bright centre to softer edge
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color, color.opacity(0.55)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 4
                    )
                )
                .frame(width: 8, height: 8)
                .scaleEffect(pulse && animate ? 1.12 : 1.0)
        }
        .animation(
            animate
                ? .easeInOut(duration: 1.3).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2),
            value: pulse
        )
        .onAppear        { pulse = animate }
        .onChange(of: animate) { _, v in pulse = v }
    }
}

// MARK: - Transcribing dots

/// Three small circles that bounce in a staggered wave — replaces the static ProgressView.
struct TranscribingDotsView: View {
    @State private var phase: Double = 0
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 5, height: 5)
                    .offset(y: CGFloat(-sin(phase + Double(i) * .pi * 2 / 3) * 4))
            }
        }
        .onReceive(timer) { _ in phase += 0.14 }
    }
}

// MARK: - Scrolling live text

/// Single-line text that types characters one-at-a-time via TypingViewModel,
/// then instantly scrolls to keep the latest character in view.
/// Left and right edges fade to transparent so text appears to emerge from / vanish into nothing.
/// The typing cadence (70 ms/char) IS the animation — no SwiftUI scroll animation needed.
struct ScrollingLiveText: View {
    let text: String

    @StateObject private var typer = TypingViewModel()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(typer.displayedText.isEmpty ? " " : typer.displayedText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(typer.displayedText.isEmpty ? 0 : 0.40))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .id("end")
            }
            .disabled(true)   // no manual scrolling
            .clipped()
            .onChange(of: typer.displayedText) { _, _ in
                // Instant scroll — the character-by-character typing is the animation
                proxy.scrollTo("end", anchor: .trailing)
            }
        }
        // Gradient mask: text fades in from the left and fades out to the right
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1.00)
                ],
                startPoint: .leading,
                endPoint:   .trailing
            )
        )
        .onChange(of: text) { _, newValue in
            typer.updateTarget(newValue)
        }
        .onAppear {
            if !text.isEmpty { typer.updateTarget(text) }
        }
        .onDisappear {
            typer.reset()
        }
    }
}

// MARK: - Soundwave bars

struct SoundwaveBars: View {
    let audioLevel: Double

    private let barCount = 7

    @State private var heights: [CGFloat] = Array(repeating: 4, count: 7)
    @State private var phase: Double = 0

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 3, height: heights[i])
                    .animation(.easeInOut(duration: 0.05), value: heights[i])
            }
        }
        .frame(height: 36)
        .onReceive(timer) { _ in
            phase += 0.35
            for i in 0..<barCount {
                let wave = sin(phase + Double(i) * 0.75)
                let normalised = 0.65 + 0.35 * wave
                let level = max(audioLevel, 0.05)
                heights[i] = 4 + CGFloat(level * 32 * normalised)
            }
        }
    }
}
