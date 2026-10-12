import Combine
import SwiftUI

struct ModelLibraryView: View {
    @ObservedObject private var downloadManager = ModelDownloadManager.shared
    @AppStorage("local_include_experimental") private var localIncludeExperimental = false
    @State private var modelFamilies: [LocalModelFamily] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var pendingWarningDownload: PendingWarningDownload?

    private let capabilityService = LocalCapabilityService()

    private struct FlatDefinitionEntry: Identifiable {
        let family: LocalModelFamily
        let definition: LocalModelDefinition
        var id: String { definition.id }
    }

    private struct PendingWarningDownload: Identifiable {
        let definition: LocalModelDefinition
        let variant: LocalModelVariant
        let warning: String
        var id: String { variant.id }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local Runtime Matrix")
                        .font(.headline)
                    Text("Only curated local Qwen and Gemma builds are exposed here. Each model can have one or more runtime variants depending on whether the device should use GGUF or MLX.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if !localIncludeExperimental {
                Section {
                    Label("Experimental Qwen and Gemma builds are hidden. Enable Show Experimental Models in Model Settings to reveal them.", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(flatDefinitions) { entry in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text(entry.definition.icon)
                            .font(.system(size: 24))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.definition.displayName)
                                .font(.headline)
                            Text(entry.definition.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    if !entry.definition.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(entry.definition.tags, id: \.self) { tag in
                                    tagBadge(for: tag)
                                }
                            }
                        }
                    }

                    Text(entry.definition.formattedCapabilities)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        ForEach(entry.definition.variants) { variant in
                            variantRow(variant, for: entry.definition)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Model Library")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadModels)
        .onChange(of: localIncludeExperimental) { _, _ in
            loadModels()
        }
        .onChange(of: downloadManager.downloadedModels) { _, _ in
            loadModels()
        }
        .onReceive(downloadManager.$latestFailure.compactMap { $0 }) { failure in
            errorMessage = failure.message
            showError = true
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Large Model Warning",
            isPresented: Binding(
                get: { pendingWarningDownload != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingWarningDownload = nil
                    }
                }
            )
        ) {
            if let pending = pendingWarningDownload {
                Button("Download Anyway") {
                    downloadVariant(pending.definition, variant: pending.variant)
                    pendingWarningDownload = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingWarningDownload = nil
            }
        } message: {
            if let warning = pendingWarningDownload?.warning {
                Text(warning)
            }
        }
    }

    private var flatDefinitions: [FlatDefinitionEntry] {
        modelFamilies.flatMap { family in
            family.definitions.map { definition in
                FlatDefinitionEntry(family: family, definition: definition)
            }
        }
    }

    @ViewBuilder
    private func variantRow(_ variant: LocalModelVariant, for definition: LocalModelDefinition) -> some View {
        let supportState = capabilityService.supportState(for: variant)
        let downloaded = downloadManager.downloadedVariantIds.contains(variant.id)
        let resumable = downloadManager.resumableDownloads.contains(variant.id)
        let lastError = downloadManager.lastErrorByVariantId[variant.id]

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.downloadLabel)
                        .font(.subheadline.weight(.semibold))
                    Text("\(variant.backendLabel) • \(variant.formattedSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if downloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let progress = downloadManager.activeDownloads[variant.id] {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 3) {
                            ProgressView(value: progress.progress)
                                .frame(width: 88)
                            Text("\(Int(progress.progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            downloadManager.cancelDownload(variantId: variant.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button(lastError == nil ? (resumable ? "Resume" : "Download") : "Retry") {
                        handleDownloadTap(definition: definition, variant: variant, supportState: supportState)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!supportState.isAvailable)
                }
            }

            Text(variant.minimumDeviceDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let progress = downloadManager.activeDownloads[variant.id] {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(formatBytes(progress.downloadedBytes)) of \(formatBytes(progress.totalBytes))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else if resumable, !downloaded {
                Label("Partial download is saved. Resume to continue.", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            if case .supportedWithWarning(let warning) = supportState {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if case .unsupported(let reason) = supportState {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let lastError {
                Label(lastError, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if downloaded {
                HStack(spacing: 12) {
                    Text("Installed")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Delete", role: .destructive) {
                        deleteVariant(variant)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func loadModels() {
        modelFamilies = LocalModelRegistry.shared.families(includeExperimental: localIncludeExperimental)
    }

    private func handleDownloadTap(
        definition: LocalModelDefinition,
        variant: LocalModelVariant,
        supportState: LocalRuntimeSupportState
    ) {
        switch supportState {
        case .supported:
            downloadVariant(definition, variant: variant)
        case .supportedWithWarning(let warning):
            pendingWarningDownload = PendingWarningDownload(
                definition: definition,
                variant: variant,
                warning: warning
            )
        case .unsupported:
            break
        }
    }

    private func tagBadge(for tag: LocalModelTag) -> some View {
        let style: (String, Color) = switch tag {
        case .recommended:
            ("Recommended", .green)
        case .experimental:
            ("Experimental", .orange)
        case .new:
            ("New", .blue)
        case .vision:
            ("Vision", .purple)
        case .highCPU:
            ("High CPU", .red)
        }

        return Text(style.0)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.1.opacity(0.15))
            .foregroundStyle(style.1)
            .clipShape(Capsule())
    }

    private func downloadVariant(_ definition: LocalModelDefinition, variant: LocalModelVariant) {
        Task {
            do {
                try await downloadManager.startDownload(definition: definition, variant: variant)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func deleteVariant(_ variant: LocalModelVariant) {
        do {
            try downloadManager.deleteVariant(variantId: variant.id)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
