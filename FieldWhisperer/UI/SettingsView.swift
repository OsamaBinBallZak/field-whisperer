import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var transcriptionEngine: TranscriptionEngine
    @State private var selectedModel: String = ModelManager.selectedModel
    @State private var axGranted  = false
    @State private var micGranted = false

    var body: some View {
        Form {
            // MARK: Model picker
            Section {
                Picker("Model", selection: $selectedModel) {
                    ForEach(ModelManager.availableModels, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedModel) { _, newValue in
                    guard newValue != ModelManager.selectedModel else { return }
                    ModelManager.selectedModel = newValue
                    Task { await transcriptionEngine.reloadModel(variant: newValue) }
                }

                // Loading state feedback
                switch transcriptionEngine.loadingState {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(transcriptionEngine.statusText)
                            .font(.caption).foregroundColor(.secondary)
                    }
                case .failed:
                    Label(transcriptionEngine.statusText, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.red)
                default:
                    Text(transcriptionEngine.statusText)
                        .font(.caption).foregroundColor(.secondary)
                }
            } header: {
                Text("Transcription Model")
            } footer: {
                Text("Models are downloaded once and cached on your Mac.\n" +
                     "Small is recommended for most users.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // MARK: Permissions
            Section("Permissions") {
                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    subtitle: "Required to insert text into focused fields",
                    granted: axGranted,
                    action: { openSystemPrivacy("Privacy_Accessibility") }
                )
                permissionRow(
                    icon: "keyboard.fill",
                    title: "Input Monitoring",
                    subtitle: "Required to detect the FN key globally",
                    granted: true,   // Cannot read this programmatically; user must verify
                    action: { openSystemPrivacy("Privacy_ListenEvent") }
                )
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Required to record your voice",
                    granted: micGranted,
                    action: { openSystemPrivacy("Privacy_Microphone") }
                )
            }

            // MARK: About
            Section("About") {
                HStack {
                    Text("FieldWhisperer").fontWeight(.medium)
                    Spacer()
                    Text("v1.0").foregroundColor(.secondary)
                }
                Text("Hold the FN key to start recording, release to transcribe and paste into any text field.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { checkPermissions() }
    }

    // MARK: - Helpers

    private func permissionRow(icon: String,
                               title: String,
                               subtitle: String,
                               granted: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.callout)
            } else {
                Button("Open Settings", action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func checkPermissions() {
        axGranted = AXIsProcessTrusted()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: micGranted = true
        default:          micGranted = false
        }
    }

    private func openSystemPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Needed for mic permission check
import AVFoundation
