import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageComposerView: View {
    @Binding var text: String
    var placeholder: String
    @FocusState.Binding var isFocused: Bool
    var isRecording: Bool
    var isSending: Bool = false
    var lineLimit: ClosedRange<Int> = 1...4
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var imageAttachments: [ImageAttachment]
    @Binding var audioAttachments: [AudioAttachment]
    var canAttachImages: Bool = false
    var canAttachAudio: Bool = false
    var onRemoveAttachment: (UUID) -> Void
    var onRemoveAudio: (UUID) -> Void
    var onAudioPicked: ([URL]) -> Void
    var onSend: () -> Void
    var onStop: (() -> Void)?
    var onRecordToggle: () async -> Void
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var controlSize: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var sendIconSize: CGFloat = 28
    @State private var showAudioImporter = false
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if isSending, let onStop {
                Button {
                    onStop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.black)
                                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop generating")
            }

            VStack(spacing: 8) {
                attachmentSection
                inputRow
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .glassStyle(.composer)
            .overlay(
                // Recording border
                Group {
                    if isRecording {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.primary, lineWidth: 2)
                    }
                }
            )
            .fileImporter(
                isPresented: $showAudioImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    onAudioPicked(urls)
                case .failure:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentSection: some View {
        if !imageAttachments.isEmpty || !audioAttachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !imageAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(imageAttachments) { attachment in
                                AttachmentPreview(
                                    data: attachment.data,
                                    onRemove: { onRemoveAttachment(attachment.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }

                if !audioAttachments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(audioAttachments) { attachment in
                            AudioAttachmentRow(
                                fileName: attachment.fileName,
                                onRemove: { onRemoveAudio(attachment.id) }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            attachmentMenu

            TextField(placeholder, text: $text, axis: .vertical)
                .font(.body)
                .lineLimit(lineLimit)
                .focused($isFocused)
                .disabled(isRecording)
                .foregroundStyle(.primary)
                .padding(.vertical, 7)
                .layoutPriority(1)

            Button {
                Task {
                    await onRecordToggle()
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isRecording ? .red : .primary)
                    .frame(width: max(controlSize, 34), height: max(controlSize, 34))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: sendIconSize, weight: .medium))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
                    .frame(width: max(controlSize, 34), height: max(controlSize, 34))
            }
            .buttonStyle(.plain)
            .disabled(!shouldShowSend || isSending)
            .opacity(shouldShowSend ? 1 : 0)
            .accessibilityLabel("Send message")
            .accessibilityHidden(!shouldShowSend)
        }
    }

    @ViewBuilder
    private var attachmentMenu: some View {
        if canAttachImages || canAttachAudio {
            Menu {
                if canAttachImages {
                    PhotosPicker(selection: $selectedPhotos, matching: .images) {
                        Label("Photo", systemImage: "photo")
                    }
                }
                if canAttachAudio {
                    Button {
                        showAudioImporter = true
                    } label: {
                        Label("Audio file", systemImage: "waveform")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: max(controlSize, 34), height: max(controlSize, 34))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityLabel("Add attachment")
        }
    }

    private var shouldShowSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !imageAttachments.isEmpty
            || !audioAttachments.isEmpty
    }
}

private struct AttachmentPreview: View {
    let data: Data
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .systemGray5))
                    .frame(width: 54, height: 54)
            }

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .background(
                        Circle().fill(.black.opacity(0.6))
                    )
            }
            .offset(x: 6, y: -6)
            .buttonStyle(.plain)
        }
    }
}

private struct AudioAttachmentRow: View {
    let fileName: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            Text(fileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.subheadline)
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .systemGray5))
        )
    }
}
