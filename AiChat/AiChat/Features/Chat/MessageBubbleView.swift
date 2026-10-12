import SwiftUI
import UIKit
import MarkdownUI


struct MessageBubbleView: View {
    let message: ChatMessage
    var paragraphText: String?
    var showTail: Bool = true
    var onClarify: (() -> Void)?
    var onTellMeMore: (() -> Void)?
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?
    var onStartSelection: (() -> Void)?
    var onQuote: ((String) -> Void)?
    var onTap: (() -> Void)?

    private var isUser: Bool { message.role == .user }
    
    private var displayText: String {
        paragraphText ?? message.text
    }

    private var attachmentPaths: [String] {
        message.attachmentPaths ?? []
    }

    private var audioAttachmentPaths: [String] {
        message.audioAttachmentPaths ?? []
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            bubble
        }
        .padding(isUser ? .leading : .trailing, 16)
    }

    private var bubble: some View {
        Group {
            if isSelectionMode {
                bubbleContent
            } else {
                bubbleContent.contextMenu {
                    if !isUser {
                        if let onClarify {
                            Button {
                                onClarify()
                            } label: {
                                Label("Clarify", systemImage: "questionmark.circle.fill")
                            }
                        }
                        if let onTellMeMore {
                            Button {
                                onTellMeMore()
                            } label: {
                                Label("Tell me more", systemImage: "text.bubble.fill")
                            }
                        }
                        Divider()
                    }
                    Button {
                        UIPasteboard.general.string = displayText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc.fill")
                    }
                    if let onStartSelection {
                        Divider()
                        Button {
                            onStartSelection()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    }
                    if let onQuote {
                        Button {
                            onQuote(displayText)
                        } label: {
                            Label("Quote", systemImage: "quote.bubble")
                        }
                    }
                }
            }
        }
    }

    private var bubbleContent: some View {
        ZStack(alignment: isUser ? .bottomTrailing : .bottomLeading) {
            // Main bubble
            VStack(alignment: .leading, spacing: 8) {
                if !attachmentPaths.isEmpty {
                    AttachmentGrid(paths: attachmentPaths)
                }

                if !audioAttachmentPaths.isEmpty {
                    AudioAttachmentList(paths: audioAttachmentPaths)
                }

                if !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Markdown(displayText)
                        .markdownTheme(.aiChat(isUserMessage: isUser))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                Group {
                    if isUser {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(white: 0.15), .black],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .systemGray5))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isUser
                            ? LinearGradient(
                                colors: [.white.opacity(0.25), .white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              )
                            : LinearGradient(
                                colors: [.white.opacity(0.15), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ),
                        lineWidth: isUser ? 1 : 0.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelectionMode && isSelected ? Color.primary : .clear, lineWidth: 2)
            )

            // Small circle instead of tail (only show for last bubble in group)
            if showTail {
                Circle()
                    .fill(
                        isUser
                            ? Color.black
                            : Color(uiColor: .systemGray5)
                    )
                    .frame(width: 8, height: 8)
                    .background(
                        Circle()
                            .stroke(isUser ? Color.white.opacity(0.1) : Color.clear, lineWidth: 0.5)
                    )
                    .offset(
                        x: isUser ? 4 : -4,
                        y: 4
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .frame(minWidth: isUser ? nil : 200)
        .overlay(alignment: isUser ? .topTrailing : .topLeading) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection?()
            } else {
                onTap?()
            }
        }
    }
}

private struct AttachmentGrid: View {
    let paths: [String]

    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(paths, id: \.self) { path in
                if let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(uiColor: .systemGray4))
                        .frame(height: 120)
                }
            }
        }
    }
}

private struct AudioAttachmentList: View {
    let paths: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(paths, id: \.self) { path in
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.secondary)
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.subheadline)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(uiColor: .systemGray4).opacity(0.3))
                )
            }
        }
    }
}
