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
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 5)

            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                    .padding(.leading, 14)

                switch viewModel.state {
                case .transcribing:
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.75).tint(.secondary)
                        Text("Transcribing…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                case .copied:
                    Text("Copied! ⌘V to paste")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()

                case .recording:
                    if viewModel.liveText.isEmpty {
                        SoundwaveBars(audioLevel: viewModel.audioLevel)
                    } else {
                        // Live transcription text scrolls in as words appear
                        Text(viewModel.liveText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .truncationMode(.head)
                            .transition(.opacity)
                    }
                    Spacer()

                case .hidden:
                    SoundwaveBars(audioLevel: 0)
                    Spacer()
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 14)
                    .opacity(viewModel.state == .hidden ? 0 : 1)
            }
        }
        .frame(width: 280, height: 64)
        .animation(.easeInOut(duration: 0.2), value: viewModel.liveText)
    }

    private var iconName: String {
        switch viewModel.state {
        case .copied: return "doc.on.clipboard"
        default:      return "mic.fill"
        }
    }

    private var iconColor: Color {
        switch viewModel.state {
        case .recording:    return .red
        case .copied:       return .green
        default:            return .secondary
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
                    .fill(Color.accentColor.opacity(0.85))
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
