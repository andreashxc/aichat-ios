import Foundation
import SwiftData

enum MessageRole: String, Codable, CaseIterable, Identifiable {
    case user
    case assistant

    var id: String { rawValue }
}

enum DeliveryState: String, Codable, CaseIterable {
    case pending
    case delivered
    case failed
    case cancelled
}

@Model
final class ChatMessage: Identifiable {
    #Index<ChatMessage>([\.conversationId], [\.createdAt], [\.conversationId, \.createdAt], [\.text])

    @Attribute(.unique) var id: UUID
    var conversationId: UUID
    var role: MessageRole
    var text: String
    var createdAt: Date
    var deliveryState: DeliveryState
    var replyToMessageId: UUID?
    var sourceProvider: ProviderID
    var attachmentPaths: [String]?
    var audioAttachmentPaths: [String]?

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        role: MessageRole,
        text: String,
        createdAt: Date = .init(),
        deliveryState: DeliveryState = .pending,
        replyToMessageId: UUID? = nil,
        sourceProvider: ProviderID,
        attachmentPaths: [String]? = nil,
        audioAttachmentPaths: [String]? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.deliveryState = deliveryState
        self.replyToMessageId = replyToMessageId
        self.sourceProvider = sourceProvider.resolvedSupportedProvider
        self.attachmentPaths = attachmentPaths
        self.audioAttachmentPaths = audioAttachmentPaths
    }
}
