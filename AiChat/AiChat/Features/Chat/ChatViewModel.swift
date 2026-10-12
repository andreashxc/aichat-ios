import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var composerText: String = ""
    @Published var isSending: Bool = false
    @Published var showTypingIndicator: Bool = false

    private let environment: AppEnvironment
    private(set) var conversation: Conversation
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?
    private let streamingFlushInterval: TimeInterval = 0.075

    private struct ProviderGenerationPlan {
        let providerId: ProviderID
        let displayName: String
        let modelId: String?
        let settings: GenerationSettings
        let generate: (ChatRequest, @escaping (String) -> Void) async throws -> String
    }

    init(environment: AppEnvironment, conversationId: UUID? = nil, autoSendFirstMessage: Bool = false) {
        self.environment = environment
        if let conversationId = conversationId,
           let existingConversation = environment.conversationStore.fetchConversation(id: conversationId) {
            self.conversation = existingConversation
        } else {
            self.conversation = environment.ensureConversation()
        }
        self.composerText = conversation.draftText ?? ""
        normalizeConversationProviderIfNeeded()
        environment.conversationStore.ensureEmojiIfNeeded(conversation)
        Task {
            await loadMessages()

            // Auto-send response if requested and there's a user message without a response
            if autoSendFirstMessage {
                let userMessages = messages.filter { $0.role == .user }
                let assistantMessages = messages.filter { $0.role == .assistant }

                // Only auto-send if there's at least one user message and no assistant responses yet
                if !userMessages.isEmpty && assistantMessages.isEmpty {
                    await sendAutoResponse()
                }
            }
        }
    }

    var navigationTitle: String {
        conversation.title
    }

    func loadMessages() async {
        messages = environment.conversationStore.fetchMessages(conversationId: conversation.id)
    }

    private func sendAutoResponse() async {
        // Get the first user message
        guard let firstUserMessage = messages.first(where: { $0.role == .user }) else { return }

        // Update conversation title if needed
        if conversation.title == "New Chat" {
            let newTitle = generateTitle(from: firstUserMessage.text)
            environment.conversationStore.updateConversationTitle(conversation, title: newTitle)
        }

        let audioAttachments = loadAudioAttachments(from: firstUserMessage.audioAttachmentPaths ?? [])

        startAssistantGeneration(userText: firstUserMessage.text, audioAttachments: audioAttachments)
    }

    func sendMessage(
        imageAttachments: [ImageAttachment] = [],
        audioAttachments: [AudioAttachment] = []
    ) {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !imageAttachments.isEmpty || !audioAttachments.isEmpty, !isSending else { return }
        
        // Clear text immediately but ensure we're on main actor
        composerText = ""
        environment.conversationStore.updateConversationDraft(conversation, draftText: nil)

        conversation.providerId = environment.providerConfig.activeProvider.resolvedSupportedProvider

        let imagePayload = buildImageAttachmentPayload(from: imageAttachments)
        let audioPayload = buildAudioAttachmentPayload(from: audioAttachments)

        let userMessage: ChatMessage
        do {
            userMessage = try environment.conversationStore.addMessage(
                text: trimmed,
                role: .user,
                conversationId: conversation.id,
                deliveryState: .delivered,
                sourceProvider: conversation.providerId,
                attachmentPaths: imagePayload.paths,
                audioAttachmentPaths: audioPayload.paths
            )
        } catch {
            AttachmentStore.deleteFiles(paths: imagePayload.paths + audioPayload.paths)
            return
        }

        // Only append if not already in messages
        if !messages.contains(where: { $0.id == userMessage.id }) {
            messages.append(userMessage)
        }

        if conversation.title == "New Chat" {
            let newTitle = generateTitle(from: trimmed)
            environment.conversationStore.updateConversationTitle(conversation, title: newTitle)
        }

        Logger.shared.info("📨 Sending message with provider: \(conversation.providerId.rawValue)")
        Logger.shared.info("📋 Active provider from config: \(environment.providerConfig.activeProvider.rawValue)")

        startAssistantGeneration(userText: trimmed, audioAttachments: audioPayload.attachments)
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        showTypingIndicator = false
        isSending = false
    }

    func sendReply(_ text: String, replyingTo message: ChatMessage) {
        guard !isSending else { return }

        conversation.providerId = environment.providerConfig.activeProvider.resolvedSupportedProvider

        let userMessage: ChatMessage
        do {
            userMessage = try environment.conversationStore.addMessage(
                text: text,
                role: .user,
                conversationId: conversation.id,
                deliveryState: .delivered,
                replyTo: message.id,
                sourceProvider: conversation.providerId
            )
        } catch {
            return
        }

        if !messages.contains(where: { $0.id == userMessage.id }) {
            messages.append(userMessage)
        }

        startAssistantGeneration(userText: text, audioAttachments: [])
    }

    private func startAssistantGeneration(userText: String, audioAttachments: [AudioAttachment]) {
        generationTask?.cancel()

        let generationID = UUID()
        activeGenerationID = generationID
        isSending = true
        showTypingIndicator = true

        generationTask = Task { [weak self] in
            guard let self else { return }
            await self.generateAssistantResponse(
                userText: userText,
                audioAttachments: audioAttachments,
                generationID: generationID
            )
        }
    }

    private func generateAssistantResponse(
        userText: String,
        audioAttachments: [AudioAttachment],
        generationID: UUID
    ) async {
        let provider = resolvedConversationProvider
        let placeholder: ChatMessage
        do {
            placeholder = try environment.conversationStore.addAssistantPlaceholder(
                conversationId: conversation.id,
                sourceProvider: provider
            )
        } catch {
            showTypingIndicator = false
            isSending = false
            return
        }
        appendMessageIfNeeded(placeholder)

        defer {
            finishGenerationIfCurrent(generationID)
        }

        var providerName = provider.displayName
        do {
            let plan = try generationPlan(for: provider)
            providerName = plan.displayName
            try await respondWithProvider(
                plan,
                userText: userText,
                audioAttachments: audioAttachments,
                placeholder: placeholder
            )
        } catch is CancellationError {
            cancelAssistantMessage(placeholder)
        } catch {
            failAssistantMessage(
                placeholder,
                text: "\(providerName) error: \(error.localizedDescription)"
            )
        }
    }

    private func generationPlan(for provider: ProviderID) throws -> ProviderGenerationPlan {
        switch provider.supportedProvider {
        case .foundationModels:
            let foundationProvider = environment.foundationModelsProvider
            let modelId = conversation.modelName ?? environment.providerConfig.foundationModel ?? "foundation-model"

            switch foundationProvider.availabilityStatus() {
            case .available:
                break
            case .unavailable(let reason):
                throw AppError.featureUnavailable(
                    """
                    Foundation Models unavailable: \(reason)
                    - Enable Apple Intelligence in Settings
                    - Check supported language/region
                    """
                )
            }

            return ProviderGenerationPlan(
                providerId: .foundationModels,
                displayName: foundationProvider.displayName,
                modelId: modelId,
                settings: GenerationSettings(model: modelId),
                generate: { request, _ in
                    try await foundationProvider.generate(request: request)
                }
            )

        case .local:
            let localProvider = environment.localProvider
            let modelId = conversation.modelName ?? environment.providerConfig.localModel
            let flushInterval = streamingFlushInterval

            return ProviderGenerationPlan(
                providerId: .local,
                displayName: localProvider.displayName,
                modelId: modelId,
                settings: GenerationSettings(
                    temperature: environment.providerConfig.temperature,
                    maxTokens: environment.providerConfig.maxTokens,
                    model: modelId
                ),
                generate: { request, onPartialResponse in
                    Logger.shared.info("ChatViewModel: Starting local model response")

                    var fullResponse = ""
                    var lastFlush = Date.distantPast

                    try await localProvider.generateStreaming(request: request) { token in
                        fullResponse += token

                        let now = Date()
                        guard now.timeIntervalSince(lastFlush) >= flushInterval else {
                            return
                        }
                        lastFlush = now
                        onPartialResponse(fullResponse)
                    }

                    let cleanedResponse = LocalResponseSanitizer.clean(fullResponse)
                    Logger.shared.info("ChatViewModel: Local model response complete (\(cleanedResponse.count) chars)")

                    guard !cleanedResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AppError.featureUnavailable("The selected local model did not generate a response. Please try again.")
                    }

                    return cleanedResponse
                }
            )
        }
    }

    private func respondWithProvider(
        _ plan: ProviderGenerationPlan,
        userText: String,
        audioAttachments: [AudioAttachment],
        placeholder: ChatMessage
    ) async throws {
        let contextMessages = environment.conversationStore.fetchMessages(conversationId: conversation.id)
        let contextProfile = ContextBudgetProfile.defaultProfile(
            providerId: plan.providerId,
            modelId: plan.modelId
        )
        let context = environment.contextBudgeter.makeContext(messages: contextMessages, profile: contextProfile)
        let finalUserText = await buildAudioAugmentedText(
            userText: userText,
            audioAttachments: audioAttachments
        )

        let request = ChatRequest(
            conversationId: conversation.id,
            userMessageText: finalUserText,
            contextMessages: context,
            settings: plan.settings,
            systemPrompt: conversation.systemPrompt
        )

        let responseText = try await plan.generate(request) { [weak self] partialResponse in
            Task { @MainActor [weak self] in
                self?.updateAssistantMessageText(placeholder, text: partialResponse, force: false)
            }
        }
        try Task.checkCancellation()
        completeAssistantMessage(placeholder, text: responseText)
    }

    private func buildImageAttachmentPayload(from attachments: [ImageAttachment]) -> (paths: [String], attachments: [ChatAttachment]) {
        guard !attachments.isEmpty else { return ([], []) }

        var paths: [String] = []
        var payload: [ChatAttachment] = []

        for attachment in attachments {
            if let path = AttachmentStore.saveImageData(attachment.data, fileExtension: attachment.fileExtension) {
                paths.append(path)
            }
            payload.append(ChatAttachment(data: attachment.data, mimeType: "image/jpeg"))
        }

        return (paths, payload)
    }

    private func buildAudioAttachmentPayload(from attachments: [AudioAttachment]) -> (paths: [String], attachments: [AudioAttachment]) {
        guard !attachments.isEmpty else { return ([], []) }

        var paths: [String] = []
        var enriched: [AudioAttachment] = []
        for attachment in attachments {
            if let path = AttachmentStore.saveAudioData(attachment.data, fileExtension: attachment.fileExtension) {
                paths.append(path)
                enriched.append(
                    AudioAttachment(
                        data: attachment.data,
                        fileExtension: attachment.fileExtension,
                        fileName: attachment.fileName,
                        mimeType: attachment.mimeType,
                        localPath: path
                    )
                )
            } else {
                enriched.append(attachment)
            }
        }
        return (paths, enriched)
    }

    private func loadImageAttachments(from paths: [String]) -> [ChatAttachment] {
        guard !paths.isEmpty else { return [] }

        var attachments: [ChatAttachment] = []
        for path in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                attachments.append(ChatAttachment(data: data, mimeType: "image/jpeg"))
            }
        }
        return attachments
    }

    private func loadAudioAttachments(from paths: [String]) -> [AudioAttachment] {
        guard !paths.isEmpty else { return [] }

        var attachments: [AudioAttachment] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension.lowercased()
            let mimeType = AttachmentStore.mimeType(forFileExtension: ext)
            attachments.append(
                AudioAttachment(
                    data: data,
                    fileExtension: ext,
                    fileName: url.lastPathComponent,
                    mimeType: mimeType,
                    localPath: path
                )
            )
        }
        return attachments
    }

    private func buildAudioAugmentedText(
        userText: String,
        audioAttachments: [AudioAttachment]
    ) async -> String {
        guard !audioAttachments.isEmpty else { return userText }

        var transcripts: [String] = []
        let selectedMode = AudioTranscriptionPreferences.selectedModel()
        for attachment in audioAttachments {
            do {
                let fileURL = try makeAudioFileURL(for: attachment)
                let transcript = try await AudioTranscriptionService.shared.transcribe(
                    fileURL: fileURL,
                    mode: selectedMode
                )
                transcripts.append(transcript)
            } catch {
                transcripts.append("Transcription failed for \(attachment.fileName): \(error.localizedDescription)")
            }
        }

        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let header = "Audio transcripts:"
        let body = transcripts.enumerated().map { index, transcript in
            "[\(index + 1)] \(transcript)"
        }.joined(separator: "\n\n")

        if trimmed.isEmpty {
            return "\(header)\n\(body)"
        }
        return "\(trimmed)\n\n\(header)\n\(body)"
    }

    private func makeAudioFileURL(for attachment: AudioAttachment) throws -> URL {
        if let localPath = attachment.localPath {
            return URL(fileURLWithPath: localPath)
        }

        let fileExtension = attachment.fileExtension.isEmpty ? "m4a" : attachment.fileExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try attachment.data.write(to: tempURL, options: [.atomic])
        return tempURL
    }

    private func loadAttachments(from paths: [String]) -> [ChatAttachment] {
        guard !paths.isEmpty else { return [] }

        var attachments: [ChatAttachment] = []
        for path in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                attachments.append(ChatAttachment(data: data, mimeType: "image/jpeg"))
            }
        }
        return attachments
    }

    private func appendMessageIfNeeded(_ message: ChatMessage) {
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
    }

    private func updateAssistantMessageText(_ message: ChatMessage, text: String, force: Bool) {
        guard force || message.deliveryState == .pending else { return }
        guard force || text.count >= message.text.count else { return }
        environment.conversationStore.updateMessageText(message, text: text)
        objectWillChange.send()
    }

    private func completeAssistantMessage(_ message: ChatMessage, text: String) {
        updateAssistantMessageText(message, text: text, force: true)
        environment.conversationStore.updateMessageDeliveryState(message, state: .delivered)
        showTypingIndicator = false
        objectWillChange.send()
    }

    private func failAssistantMessage(_ message: ChatMessage, text: String) {
        updateAssistantMessageText(message, text: text, force: true)
        environment.conversationStore.updateMessageDeliveryState(message, state: .failed)
        showTypingIndicator = false
        objectWillChange.send()
    }

    private func cancelAssistantMessage(_ message: ChatMessage) {
        Logger.shared.info("ChatViewModel: Generation cancelled")
        if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            environment.conversationStore.deleteMessage(message)
            messages.removeAll { $0.id == message.id }
        } else {
            environment.conversationStore.updateMessageDeliveryState(message, state: .cancelled)
        }
        showTypingIndicator = false
        objectWillChange.send()
    }

    private func finishGenerationIfCurrent(_ generationID: UUID) {
        guard activeGenerationID == generationID else { return }
        showTypingIndicator = false
        isSending = false
        generationTask = nil
        activeGenerationID = nil
    }

    func updateTitle(_ newTitle: String) {
        environment.conversationStore.updateConversationTitle(conversation, title: newTitle)
        objectWillChange.send()
    }

    func updateEmoji(_ newEmoji: String) {
        environment.conversationStore.updateConversationEmoji(conversation, emoji: newEmoji)
        objectWillChange.send()
    }

    func updateModel(provider: ProviderID, modelId: String) {
        conversation.providerId = provider.resolvedSupportedProvider
        conversation.modelName = modelId
        environment.conversationStore.saveConversation(conversation)
        objectWillChange.send()

        // Preload local model to avoid UI lag when user starts typing
        if provider.resolvedSupportedProvider == .local {
            Task { [weak self] in
                guard let self = self else { return }
                Logger.shared.info("🔄 Preloading local model: \(modelId)")
                do {
                    try await self.environment.localProvider.loadModel(modelName: modelId)
                    Logger.shared.info("✅ Local model preloaded successfully")
                } catch {
                    Logger.shared.error("❌ Failed to preload model: \(error.localizedDescription)")
                }
            }
        }
    }

    func deleteConversation() {
        do {
            try environment.conversationStore.deleteConversation(conversation)
        } catch {}
    }

    func persistDraftAndCleanupIfNeeded() {
        let trimmedDraft = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingMessages = environment.conversationStore.fetchMessages(conversationId: conversation.id)

        if existingMessages.isEmpty {
            if trimmedDraft.isEmpty {
                do {
                    try environment.conversationStore.deleteConversation(conversation)
                } catch {}
                return
            } else {
                environment.conversationStore.updateConversationDraft(conversation, draftText: trimmedDraft)
                return
            }
        }

        if trimmedDraft.isEmpty {
            environment.conversationStore.updateConversationDraft(conversation, draftText: nil)
        } else {
            environment.conversationStore.updateConversationDraft(conversation, draftText: trimmedDraft)
        }
    }

    private func generateTitle(from text: String) -> String {
        let words = text.split(separator: " ")
        let maxWords = min(6, words.count)
        let titleWords = words.prefix(maxWords).joined(separator: " ")
        return titleWords + (words.count > maxWords ? "..." : "")
    }

    private var resolvedConversationProvider: ProviderID {
        conversation.providerId.resolvedSupportedProvider
    }

    private func normalizeConversationProviderIfNeeded() {
        let normalizedProvider = conversation.providerId.resolvedSupportedProvider
        guard conversation.providerId != normalizedProvider else { return }

        conversation.providerId = normalizedProvider
        if normalizedProvider == .foundationModels {
            conversation.modelName = environment.providerConfig.foundationModel ?? "foundation-model"
        }
        environment.conversationStore.saveConversation(conversation)
    }
}
