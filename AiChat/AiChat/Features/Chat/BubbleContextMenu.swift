import SwiftUI
import UIKit

struct BubbleContextMenu: ViewModifier {
    let message: ChatMessage
    let onClarify: (() -> Void)?
    let onTellMeMore: (() -> Void)?

    func body(content: Content) -> some View {
        content.contextMenu {
            if let onClarify {
                Button("Clarify…", action: onClarify)
            }
            if let onTellMeMore {
                Button("Tell me more", action: onTellMeMore)
            }
            Button {
                UIPasteboard.general.string = message.text
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

extension View {
    func bubbleContextMenu(
        for message: ChatMessage,
        onClarify: (() -> Void)? = nil,
        onTellMeMore: (() -> Void)? = nil
    ) -> some View {
        modifier(
            BubbleContextMenu(
                message: message,
                onClarify: onClarify,
                onTellMeMore: onTellMeMore
            )
        )
    }
}
