import SwiftUI

struct SettingsView: View {
    @ObservedObject var environment: AppEnvironment
    let showsCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var attachmentCleanupResult: String?

    init(environment: AppEnvironment, showsCloseButton: Bool = false) {
        self.environment = environment
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Form {
            Section("Models") {
                NavigationLink("Provider Settings") {
                    ProviderSettingsView(environment: environment)
                }
                NavigationLink("Model Library") {
                    ModelLibraryView()
                }
            }

            Section("Device Information") {
                NavigationLink("Device Diagnostics") {
                    DeviceDiagnosticsView()
                }
            }

            Section("Storage") {
                Button("Clean orphaned attachments") {
                    cleanOrphanedAttachments()
                }

                if let attachmentCleanupResult {
                    Text(attachmentCleanupResult)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let persistenceError = environment.persistenceError {
                Section("Persistence") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(persistenceError.operation)
                            .font(.subheadline.weight(.semibold))
                        Text(persistenceError.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Dismiss") {
                        environment.clearPersistenceError()
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close Settings")
                }
            }
        }
    }

    private func cleanOrphanedAttachments() {
        let messages = environment.conversationStore.fetchAllMessages()
        let reclaimedBytes = AttachmentStore.cleanupOrphanedAttachments(existingMessages: messages)
        let reclaimed = AttachmentStore.formattedByteCount(reclaimedBytes)
        attachmentCleanupResult = "Reclaimed \(reclaimed)"
        Logger.shared.info("Cleaned orphaned attachments, reclaimed \(reclaimed)")
    }
}
