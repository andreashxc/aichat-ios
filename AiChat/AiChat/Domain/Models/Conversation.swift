import Foundation
import SwiftData

@Model
final class Conversation: Identifiable {
    #Index<Conversation>([\.updatedAt], [\.title])

    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var providerId: ProviderID
    var modelName: String?
    var emoji: String?
    var systemPrompt: String?
    var draftText: String?
    var lastMessagePreview: String?
    var lastMessageDate: Date?
    var lastMessageRole: MessageRole?
    var messageCount: Int

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .init(),
        updatedAt: Date = .init(),
        providerId: ProviderID,
        modelName: String? = nil,
        emoji: String? = Conversation.randomEmoji(),
        systemPrompt: String? = nil,
        draftText: String? = nil,
        lastMessagePreview: String? = nil,
        lastMessageDate: Date? = nil,
        lastMessageRole: MessageRole? = nil,
        messageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.providerId = providerId.resolvedSupportedProvider
        self.modelName = modelName
        self.emoji = emoji
        self.systemPrompt = systemPrompt
        self.draftText = draftText
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageDate = lastMessageDate
        self.lastMessageRole = lastMessageRole
        self.messageCount = messageCount
    }

    static func randomEmoji() -> String {
        defaultChatEmoji
    }

    static let defaultChatEmoji = "👋"
    static let agentChatEmoji = "🤖"

    static func emoji(forSystemPrompt systemPrompt: String?) -> String {
        systemPrompt == nil ? defaultChatEmoji : agentChatEmoji
    }
}
