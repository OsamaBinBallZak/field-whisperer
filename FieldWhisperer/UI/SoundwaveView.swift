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
                // Solid dark background for maximum contrast
                Capsule()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.94))
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 7)

                HStack(spacing: 0) {
                    // Mic / checkmark icon — faint blue bloom behind it during recording
                    ZStack {
                        if viewModel.state == .recording {
                            Circle()
                                .fill(Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.18))
                                .frame(width: 28, height: 28)
                                .blur(radius: 5)
                        }
                        Image(systemName: iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
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
        case .recording:    return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .transcribing: return .orange
        case .copied:       return .green
        case .hidden:       return .clear
        }
    }
}

// MARK: - Animated status dot

/// Three-layer LED-style dot: dark housing/bezel, offset-specular lit core,
/// and a soft bloom that bleeds outward during recording.
struct AnimatedDot: View {
    let color: Color
    let animate: Bool

    @State private var pulse = false

    var body: some View {
        ZStack {
            // Layer 1: outer bloom — blurred glow bleeding outside the housing
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .blur(radius: 5)
                .opacity(animate ? (pulse ? 0.50 : 0.08) : 0)

            // Layer 2: dark housing/bezel ring
            Circle()
                .fill(Color(white: 0.10))
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(Color(white: 0.25), lineWidth: 0.5))

            // Layer 3: inner lit core — off-centre radial gradient creates a
            // top-left specular highlight matching the reference LED image
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, color, color.opacity(0.35)],
                        center: UnitPoint(x: 0.35, y: 0.28),
                        startRadius: 0,
                        endRadius: 5
                    )
                )
                .frame(width: 9, height: 9)
                .opacity(animate ? (pulse ? 1.0 : 0.45) : 0.20)
                .scaleEffect(animate ? (pulse ? 1.0 : 0.82) : 0.65)
        }
        .frame(width: 22, height: 22)
        .onAppear {
            guard animate else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: animate) { _, v in
            if v {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { pulse = false }
            }
        }
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
