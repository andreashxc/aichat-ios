import Foundation

struct ContextMessage: Identifiable, Codable, Hashable {
    let id: UUID
    let role: MessageRole
    let text: String
    let replyToMessageId: UUID?
}

struct ChatRequest: Codable, Hashable {
    let conversationId: UUID
    let userMessageText: String
    let replyToMessageId: UUID?
    let targetMessageText: String?
    let contextMessages: [ContextMessage]
    let attachments: [ChatAttachment]
    var settings: GenerationSettings
    let systemPrompt: String?

    init(
        conversationId: UUID,
        userMessageText: String,
        replyToMessageId: UUID? = nil,
        targetMessageText: String? = nil,
        contextMessages: [ContextMessage] = [],
        attachments: [ChatAttachment] = [],
        settings: GenerationSettings = GenerationSettings(),
        systemPrompt: String? = nil
    ) {
        self.conversationId = conversationId
        self.userMessageText = userMessageText
        self.replyToMessageId = replyToMessageId
        self.targetMessageText = targetMessageText
        self.contextMessages = contextMessages
        self.attachments = attachments
        self.settings = settings
        self.systemPrompt = systemPrompt
    }
}
