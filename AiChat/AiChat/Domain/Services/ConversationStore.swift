import Foundation
import SwiftData

@MainActor
final class ConversationStore {
    private let modelContext: ModelContext
    var persistenceErrorHandler: ((String, Error) -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func bootstrapConversation(defaultProvider: ProviderID) -> Conversation {
        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            let normalizedProvider = existing.providerId.resolvedSupportedProvider
            if existing.providerId != normalizedProvider {
                existing.providerId = normalizedProvider
                if normalizedProvider == .foundationModels {
                    existing.modelName = "foundation-model"
                }
                saveSilently(operation: "Normalize conversation provider")
            }
            return existing
        }

        let conversation = Conversation(
            title: "New Chat",
            providerId: defaultProvider.resolvedSupportedProvider,
            modelName: nil
        )
        modelContext.insert(conversation)
        saveSilently(operation: "Bootstrap conversation")
        return conversation
    }

    func createConversation(
        title: String,
        providerId: ProviderID,
        modelName: String? = nil,
        emoji: String? = nil,
        systemPrompt: String? = nil
    ) throws -> Conversation {
        let resolvedEmoji = emoji ?? Conversation.emoji(forSystemPrompt: systemPrompt)
        let resolvedProvider = providerId.resolvedSupportedProvider
        let conversation = Conversation(
            title: title,
            providerId: resolvedProvider,
            modelName: resolvedProvider == .foundationModels ? (modelName ?? "foundation-model") : modelName,
            emoji: resolvedEmoji,
            systemPrompt: systemPrompt
        )
        modelContext.insert(conversation)
        try save(operation: "Create conversation")
        return conversation
    }

    func deleteConversation(_ conversation: Conversation) throws {
        let messages = fetchMessages(conversationId: conversation.id)
        let attachmentPaths = messages.flatMap { message in
            (message.attachmentPaths ?? []) + (message.audioAttachmentPaths ?? [])
        }
        for message in messages {
            modelContext.delete(message)
        }
        modelContext.delete(conversation)
        try save(operation: "Delete conversation")
        AttachmentStore.deleteFiles(paths: attachmentPaths)
    }

    func fetchAllConversations() -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchAllMessages() -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func updateConversationTitle(_ conversation: Conversation, title: String) {
        conversation.title = title
        conversation.updatedAt = Date()
        saveSilently(operation: "Update conversation title")
    }

    func updateConversationEmoji(_ conversation: Conversation, emoji: String) {
        conversation.emoji = emoji
        conversation.updatedAt = Date()
        saveSilently(operation: "Update conversation emoji")
    }

    func updateConversationDraft(_ conversation: Conversation, draftText: String?) {
        let trimmed = draftText?.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.draftText = trimmed?.isEmpty == false ? trimmed : nil
        conversation.updatedAt = Date()
        saveSilently(operation: "Update conversation draft")
    }

    func saveConversation(_ conversation: Conversation) {
        conversation.updatedAt = Date()
        saveSilently(operation: "Save conversation")
    }

    func ensureEmojiIfNeeded(_ conversation: Conversation) {
        let trimmed = (conversation.emoji ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return }
        conversation.emoji = Conversation.emoji(forSystemPrompt: conversation.systemPrompt)
        saveSilently(operation: "Ensure conversation emoji")
    }

    func fetchConversation(id: UUID) -> Conversation? {
        var descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.id == id },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func fetchMessages(conversationId: UUID) -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchConversationIDsMatchingMessageText(_ searchText: String) -> Set<UUID> {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else { return [] }

        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { message in
                message.text.localizedStandardContains(trimmedSearchText)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let messages = (try? modelContext.fetch(descriptor)) ?? []
        return Set(messages.map(\.conversationId))
    }

    func backfillConversationDerivedFieldsIfNeeded() {
        let conversations = fetchAllConversations()
        var didChange = false

        for conversation in conversations where conversation.messageCount == 0 && conversation.lastMessageDate == nil && conversation.lastMessagePreview == nil {
            let count = fetchMessageCount(conversationId: conversation.id)
            guard count > 0 else { continue }
            refreshDerivedFields(for: conversation)
            didChange = true
        }

        if didChange {
            saveSilently(operation: "Backfill conversation summaries")
        }
    }

    @discardableResult
    func addMessage(
        text: String,
        role: MessageRole,
        conversationId: UUID,
        createdAt: Date = .init(),
        deliveryState: DeliveryState = .delivered,
        replyTo: UUID? = nil,
        sourceProvider: ProviderID,
        attachmentPaths: [String]? = nil,
        audioAttachmentPaths: [String]? = nil
    ) throws -> ChatMessage {
        let message = ChatMessage(
            conversationId: conversationId,
            role: role,
            text: text,
            createdAt: createdAt,
            deliveryState: deliveryState,
            replyToMessageId: replyTo,
            sourceProvider: sourceProvider,
            attachmentPaths: attachmentPaths,
            audioAttachmentPaths: audioAttachmentPaths
        )
        modelContext.insert(message)
        if let conversation = fetchConversation(id: conversationId) {
            conversation.updatedAt = Date()
            conversation.messageCount += 1
            if shouldReplaceLastMessageSummary(conversation: conversation, with: message) {
                applyLastMessageSummary(message, to: conversation)
            }
        }
        try save(operation: "Add message")
        return message
    }

    @discardableResult
    func addAssistantPlaceholder(
        conversationId: UUID,
        sourceProvider: ProviderID
    ) throws -> ChatMessage {
        try addMessage(
            text: "",
            role: .assistant,
            conversationId: conversationId,
            deliveryState: .pending,
            sourceProvider: sourceProvider
        )
    }

    func updateMessageText(_ message: ChatMessage, text: String) {
        message.text = text
        if let conversation = fetchConversation(id: message.conversationId) {
            conversation.updatedAt = Date()
            if conversation.lastMessageDate == message.createdAt {
                applyLastMessageSummary(message, to: conversation)
            }
        }
        saveSilently(operation: "Update message text")
    }

    func updateMessageDeliveryState(_ message: ChatMessage, state: DeliveryState) {
        message.deliveryState = state
        if let conversation = fetchConversation(id: message.conversationId) {
            conversation.updatedAt = Date()
            if conversation.lastMessageDate == message.createdAt {
                applyLastMessageSummary(message, to: conversation)
            }
        }
        saveSilently(operation: "Update message delivery state")
    }

    func deleteMessage(_ message: ChatMessage) {
        let attachmentPaths = (message.attachmentPaths ?? []) + (message.audioAttachmentPaths ?? [])
        let conversationId = message.conversationId
        if let conversation = fetchConversation(id: conversationId) {
            conversation.updatedAt = Date()
            refreshDerivedFields(for: conversation, excluding: message.id)
        }
        modelContext.delete(message)
        if saveSilently(operation: "Delete message") {
            AttachmentStore.deleteFiles(paths: attachmentPaths)
        }
    }

    private func fetchLatestMessage(conversationId: UUID, excluding excludedMessageId: UUID? = nil) -> ChatMessage? {
        let descriptor: FetchDescriptor<ChatMessage>
        if let excludedMessageId {
            var excludingDescriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { message in
                    message.conversationId == conversationId && message.id != excludedMessageId
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            excludingDescriptor.fetchLimit = 1
            descriptor = excludingDescriptor
        } else {
            var allMessagesDescriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { message in
                    message.conversationId == conversationId
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            allMessagesDescriptor.fetchLimit = 1
            descriptor = allMessagesDescriptor
        }

        return try? modelContext.fetch(descriptor).first
    }

    private func fetchMessageCount(conversationId: UUID, excluding excludedMessageId: UUID? = nil) -> Int {
        let descriptor: FetchDescriptor<ChatMessage>
        if let excludedMessageId {
            descriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { message in
                    message.conversationId == conversationId && message.id != excludedMessageId
                }
            )
        } else {
            descriptor = FetchDescriptor<ChatMessage>(
                predicate: #Predicate { message in
                    message.conversationId == conversationId
                }
            )
        }

        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func refreshDerivedFields(for conversation: Conversation, excluding excludedMessageId: UUID? = nil) {
        conversation.messageCount = fetchMessageCount(conversationId: conversation.id, excluding: excludedMessageId)
        guard let latestMessage = fetchLatestMessage(conversationId: conversation.id, excluding: excludedMessageId) else {
            conversation.lastMessagePreview = nil
            conversation.lastMessageDate = nil
            conversation.lastMessageRole = nil
            return
        }

        applyLastMessageSummary(latestMessage, to: conversation)
    }

    private func shouldReplaceLastMessageSummary(conversation: Conversation, with message: ChatMessage) -> Bool {
        guard let lastMessageDate = conversation.lastMessageDate else { return true }
        return message.createdAt >= lastMessageDate
    }

    private func applyLastMessageSummary(_ message: ChatMessage, to conversation: Conversation) {
        conversation.lastMessagePreview = message.text
        conversation.lastMessageDate = message.createdAt
        conversation.lastMessageRole = message.role
    }

    private func save(operation: String) throws {
        do {
            try modelContext.save()
        } catch {
            reportPersistenceError(error, operation: operation)
            throw error
        }
    }

    @discardableResult
    private func saveSilently(operation: String) -> Bool {
        do {
            try save(operation: operation)
            return true
        } catch {}
        return false
    }

    private func reportPersistenceError(_ error: Error, operation: String) {
        Logger.shared.error("SwiftData save failed during \(operation): \(error.localizedDescription)")
        persistenceErrorHandler?(operation, error)
    }
}
