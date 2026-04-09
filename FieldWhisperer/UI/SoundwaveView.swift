import SwiftUI

// MARK: - View model

enum RecordingUIState {
    case hidden
    case recording
    case transcribing
}

@MainActor
final class SoundwaveViewModel: ObservableObject {
    @Published var state: RecordingUIState = .hidden
    @Published var audioLevel: Double = 0
}

// MARK: - Root view

struct SoundwaveView: View {
    @ObservedObject var viewModel: SoundwaveViewModel

    var body: some View {
        ZStack {
            // Frosted-glass pill background
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 5)

            HStack(spacing: 10) {
                // Microphone icon – red while recording
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(viewModel.state == .recording ? .red : .secondary)
                    .padding(.leading, 14)

                if viewModel.state == .transcribing {
                    // Transcribing indicator
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.75)
                            .tint(.secondary)
                        Text("Transcribing…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    // Animated soundwave bars
                    SoundwaveBars(audioLevel: viewModel.audioLevel)
                    Spacer()
                }

                // Recording status dot
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.trailing, 14)
                    .opacity(viewModel.state == .hidden ? 0 : 1)
            }
        }
        .frame(width: 280, height: 64)
    }

    private var dotColor: Color {
        switch viewModel.state {
        case .recording:    return .red
        case .transcribing: return .orange
        case .hidden:       return .clear
        }
    }
}

// MARK: - Soundwave bars

struct SoundwaveBars: View {
    let audioLevel: Double

    private let barCount = 7
    private let updateInterval: TimeInterval = 0.05

    @State private var heights: [CGFloat] = Array(repeating: 4, count: 7)
    @State private var phase: Double = 0

    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 3, height: heights[i])
                    .animation(.easeInOut(duration: updateInterval), value: heights[i])
            }
        }
        .frame(height: 36)
        .onReceive(timer) { _ in
            phase += 0.35
            for i in 0..<barCount {
                let wave = sin(phase + Double(i) * 0.75)      // -1 … 1
                let normalised = 0.65 + 0.35 * wave            // 0.3 … 1.0
                let level = max(audioLevel, 0.05)              // always gently animated
                heights[i] = 4 + CGFloat(level * 32 * normalised)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct SoundwaveView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = SoundwaveViewModel()
        vm.state = .recording
        vm.audioLevel = 0.6
        return SoundwaveView(viewModel: vm)
            .frame(width: 300, height: 80)
            .background(Color.gray.opacity(0.2))
    }
}
#endif
