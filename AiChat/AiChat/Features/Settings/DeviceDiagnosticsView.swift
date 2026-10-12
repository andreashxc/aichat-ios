import SwiftUI

struct DeviceDiagnosticsView: View {
    @State private var diagnosticText: String = ""
    @State private var profile = DeviceCapabilities.currentProfile()
    @State private var showCopiedAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Device Diagnostics")
                            .font(.title2)
                            .bold()
                    }

                    Text("Information about your device and ML capabilities")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)

                Divider()

                // MLX Support Status
                mlxSupportSection

                Divider()

                // Diagnostic Text
                diagnosticTextSection

                // Copy Button
                Button(action: copyDiagnostics) {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .navigationTitle("Device Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Diagnostics copied to clipboard")
        }
        .onAppear {
            loadDiagnostics()
        }
    }

    // MARK: - MLX Support Section

    private var mlxSupportSection: some View {
        VStack(spacing: 12) {
            // MLX Support Badge
            HStack {
                Image(systemName: profile.supportsMLX ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(profile.supportsMLX ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MLX Support")
                        .font(.headline)
                    Text(profile.supportsMLX ? "Your device supports MLX acceleration" : "MLX not available on this device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Recommended Engine
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.title3)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommended Engine")
                        .font(.headline)
                    Text(profile.recommendedBackend.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(profile.recommendedBackend.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - Diagnostic Text Section

    private var diagnosticTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Full Diagnostic Report")
                .font(.headline)
                .padding(.horizontal)

            Text(diagnosticText)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }

    // MARK: - Actions

    private func loadDiagnostics() {
        profile = DeviceCapabilities.currentProfile()
        Logger.shared.info("MLX Support in UI: \(profile.supportsMLX)")
        diagnosticText = DeviceCapabilities.diagnosticInfo()
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = diagnosticText
        showCopiedAlert = true
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeviceDiagnosticsView()
    }
}
