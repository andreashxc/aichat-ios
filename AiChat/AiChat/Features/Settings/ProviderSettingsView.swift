import SwiftUI

struct ProviderSettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @State private var foundationAvailability: FoundationModelsAvailabilityStatus = .unavailable("Not checked")
    @State private var audioTranscriptionModel: AudioTranscriptionModel = .tiny
    @State private var localBackendPreference: LocalBackendPreference = .auto
    @State private var localThinkingMode: LocalThinkingModePreference = .automatic
    @State private var localIncludeExperimental = false
    @State private var localProviderStatus: String = "No local model downloaded"
    @State private var localRuntimeStatus: LocalRuntimeStatus = .idle

    var body: some View {
        Form {
            Section("Foundation Models") {
                VStack(alignment: .leading, spacing: 8) {
                    availabilityLabel
                    Text("Apple Foundation Models stay available as the system-native option. Everything else in the app now routes through local runtimes only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Re-check availability") {
                        refreshAvailability()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Section("Local Models") {
                Picker("Backend", selection: $localBackendPreference) {
                    ForEach(LocalBackendPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Thinking Mode", selection: $localThinkingMode) {
                    ForEach(LocalThinkingModePreference.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Show Experimental Models", isOn: $localIncludeExperimental)

                Text("Only Apple Foundation Models plus curated local Qwen and Gemma variants are exposed now. Unsupported runtimes are hidden before download or load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(localProviderStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                runtimeStatusRow
            }

            Section("Audio Transcription") {
                Picker("Model", selection: $audioTranscriptionModel) {
                    ForEach(AudioTranscriptionModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.inline)

                Text("Audio is transcribed on-device first, then sent into the selected Foundation or local model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Model Settings")
        .onAppear {
            refreshAvailability()
            loadPreferences()
            Task {
                await refreshLocalStatus()
            }
        }
        .onChange(of: audioTranscriptionModel) { _, newValue in
            AudioTranscriptionPreferences.saveSelectedModel(newValue)
        }
        .onChange(of: localBackendPreference) { _, newValue in
            ModelPreferences.localBackendPreference = newValue
            Task {
                await refreshLocalStatus()
            }
        }
        .onChange(of: localThinkingMode) { _, newValue in
            ModelPreferences.localThinkingMode = newValue
        }
        .onChange(of: localIncludeExperimental) { _, newValue in
            ModelPreferences.localIncludeExperimental = newValue
            ModelDownloadManager.shared.refreshDownloadedModels()
            Task {
                await refreshLocalStatus()
            }
        }
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        switch foundationAvailability {
        case .available:
            Text("Model ready on this device.")
        case .unavailable(let reason):
            Text(reason)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshAvailability() {
        foundationAvailability = environment.foundationModelsProvider.availabilityStatus()
    }

    private func loadPreferences() {
        audioTranscriptionModel = AudioTranscriptionPreferences.selectedModel()
        localBackendPreference = ModelPreferences.localBackendPreference
        localThinkingMode = ModelPreferences.localThinkingMode
        localIncludeExperimental = ModelPreferences.localIncludeExperimental
    }

    private var runtimeStatusRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(localRuntimeStatus.phase.displayName, systemImage: runtimeStatusIcon)
                Spacer()
                if let backend = localRuntimeStatus.backend {
                    Text(backend.displayName)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

            if let modelId = localRuntimeStatus.currentModelId {
                Text(modelId)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let tokensPerSecond = localRuntimeStatus.tokensPerSecond {
                Text("\(String(format: "%.1f", tokensPerSecond)) tokens/sec")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let message = localRuntimeStatus.message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(localRuntimeStatus.phase == .error ? .red : .secondary)
            }
        }
    }

    private var runtimeStatusIcon: String {
        switch localRuntimeStatus.phase {
        case .idle:
            return "pause.circle"
        case .loading:
            return "arrow.down.circle"
        case .loaded:
            return "checkmark.circle"
        case .generating:
            return "waveform"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private func refreshLocalStatus() async {
        localProviderStatus = await environment.localProvider.providerStatus
        localRuntimeStatus = await environment.localProvider.runtimeStatus
    }
}
