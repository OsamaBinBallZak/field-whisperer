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
}

// MARK: - Root view

struct SoundwaveView: View {
    @ObservedObject var viewModel: SoundwaveViewModel

    var body: some View {
        ZStack {
            // Dark high-contrast pill
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.94))
                .shadow(color: .black.opacity(0.45), radius: 16, y: 6)

            HStack(spacing: 0) {
                // Mic / clipboard icon
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)

                switch viewModel.state {
                case .recording:
                    // Bars always visible at fixed width
                    SoundwaveBars(audioLevel: viewModel.audioLevel)
                        .frame(width: 36)
                    // Scrolling live text fills the remaining space
                    ScrollingLiveText(text: viewModel.liveText)
                        .padding(.horizontal, 8)

                case .transcribing:
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.white.opacity(0.6))
                        Text("Transcribing…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
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

                // Status dot
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 14)
                    .padding(.leading, 6)
                    .opacity(viewModel.state == .hidden ? 0 : 1)
            }
        }
        .frame(width: 320, height: 56)
    }

    private var iconName: String {
        switch viewModel.state {
        case .copied: return "doc.on.clipboard"
        default:      return "mic.fill"
        }
    }

    private var iconColor: Color {
        switch viewModel.state {
        case .recording: return .red
        case .copied:    return .green
        default:         return .white.opacity(0.55)
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

// MARK: - Scrolling live text

/// Single-line text that auto-scrolls right as new words arrive,
/// so the latest transcription is always visible.
struct ScrollingLiveText: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(text.isEmpty ? 0 : 0.9))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .id("end")
            }
            .disabled(true)   // prevent manual scrolling
            .clipped()
            .onChange(of: text) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("end", anchor: .trailing)
                }
            }
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
