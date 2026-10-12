import SwiftUI
import MarkdownUI

extension Theme {
    /// Custom Markdown theme for AiChat's glass-material chat styling.
    static func aiChat(isUserMessage: Bool) -> Theme {
        Theme()
            .text {
                ForegroundColor(isUserMessage ? .white : .primary)
                FontSize(16)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.94))
                ForegroundColor(isUserMessage ? .white.opacity(0.95) : .primary)
                BackgroundColor(isUserMessage ? .white.opacity(0.15) : .black.opacity(0.05))
            }
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .link {
                ForegroundColor(isUserMessage ? .white : .blue)
                UnderlineStyle(.single)
            }
            .heading1 { configuration in
                VStack(alignment: .leading, spacing: 8) {
                    configuration.label
                        .markdownTextStyle {
                            FontWeight(.bold)
                            FontSize(.em(1.5))
                        }
                    Divider()
                        .overlay(isUserMessage ? Color.white.opacity(0.3) : Color.gray.opacity(0.3))
                }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.3))
                    }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.15))
                    }
            }
            .paragraph { configuration in
                configuration.label
                    .padding(.vertical, 4)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isUserMessage ? .white.opacity(0.15) : .black.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    isUserMessage ? .white.opacity(0.2) : .gray.opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                }
                .padding(.vertical, 4)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: 2, bottom: 2)
            }
            // Use default bullet markers from Markdown
            .bulletedListMarker { _ in
                Text("•")
                    .foregroundColor(isUserMessage ? .white.opacity(0.8) : .secondary)
            }
            .blockquote { configuration in
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isUserMessage ? .white.opacity(0.4) : .blue.opacity(0.5))
                        .frame(width: 4)
                    configuration.label
                        .markdownTextStyle {
                            FontStyle(.italic)
                        }
                }
                .padding(.vertical, 8)
            }
    }
}
