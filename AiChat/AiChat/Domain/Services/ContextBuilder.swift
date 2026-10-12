import Foundation

struct ContextBudgetProfile: Hashable {
    let providerId: ProviderID
    let modelId: String?
    let maxCharacters: Int
    let maxMessages: Int
    let preserveSystemPrompt: Bool
    let preserveLastUserMessage: Bool
    let includeAssistantMessages: Bool
    let includeFailedMessages: Bool

    init(
        providerId: ProviderID,
        modelId: String?,
        maxCharacters: Int,
        maxMessages: Int,
        preserveSystemPrompt: Bool,
        preserveLastUserMessage: Bool,
        includeAssistantMessages: Bool,
        includeFailedMessages: Bool = false
    ) {
        self.providerId = providerId.resolvedSupportedProvider
        self.modelId = modelId
        self.maxCharacters = maxCharacters
        self.maxMessages = maxMessages
        self.preserveSystemPrompt = preserveSystemPrompt
        self.preserveLastUserMessage = preserveLastUserMessage
        self.includeAssistantMessages = includeAssistantMessages
        self.includeFailedMessages = includeFailedMessages
    }

    static func defaultProfile(providerId: ProviderID, modelId: String?) -> ContextBudgetProfile {
        switch providerId.supportedProvider {
        case .foundationModels:
            return foundationModels(modelId: modelId)
        case .local:
            return local(modelId: modelId)
        }
    }

    static func foundationModels(modelId: String?) -> ContextBudgetProfile {
        ContextBudgetProfile(
            providerId: .foundationModels,
            modelId: modelId,
            maxCharacters: 24_000,
            maxMessages: 36,
            preserveSystemPrompt: true,
            preserveLastUserMessage: true,
            includeAssistantMessages: true
        )
    }

    static func local(modelId: String?) -> ContextBudgetProfile {
        if let size = parameterSizeBillions(from: modelId), size > 2 {
            return localMedium(modelId: modelId)
        }
        return localSmall(modelId: modelId)
    }

    static func localSmall(modelId: String?) -> ContextBudgetProfile {
        ContextBudgetProfile(
            providerId: .local,
            modelId: modelId,
            maxCharacters: 6_000,
            maxMessages: 10,
            preserveSystemPrompt: true,
            preserveLastUserMessage: true,
            includeAssistantMessages: true
        )
    }

    static func localMedium(modelId: String?) -> ContextBudgetProfile {
        ContextBudgetProfile(
            providerId: .local,
            modelId: modelId,
            maxCharacters: 12_000,
            maxMessages: 18,
            preserveSystemPrompt: true,
            preserveLastUserMessage: true,
            includeAssistantMessages: true
        )
    }

    private static func parameterSizeBillions(from modelId: String?) -> Double? {
        guard let modelId else { return nil }
        let pattern = #"(?i)(?:^|[^0-9])([1-4](?:\.\d+)?)b(?:[^a-z0-9]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(modelId.startIndex..<modelId.endIndex, in: modelId)
        guard let match = regex.firstMatch(in: modelId, range: range),
              let valueRange = Range(match.range(at: 1), in: modelId) else {
            return nil
        }
        return Double(String(modelId[valueRange]))
    }
}

struct ContextBudgeter {
    func makeContext(messages: [ChatMessage], profile: ContextBudgetProfile) -> [ContextMessage] {
        guard profile.maxMessages > 0, profile.maxCharacters > 0 else { return [] }

        var selected = messages
            .sorted(by: { $0.createdAt < $1.createdAt })
            .compactMap { makeContextMessage(from: $0, profile: profile) }

        let protectedMessageIds: Set<UUID>
        if profile.preserveLastUserMessage,
           let lastUserMessage = selected.last(where: { $0.role == .user }) {
            protectedMessageIds = [lastUserMessage.id]
        } else {
            protectedMessageIds = []
        }

        pruneMessageCount(
            in: &selected,
            maxMessages: profile.maxMessages,
            protectedMessageIds: protectedMessageIds
        )
        pruneCharacterCount(
            in: &selected,
            maxCharacters: profile.maxCharacters,
            protectedMessageIds: protectedMessageIds
        )

        return selected
    }

    private func makeContextMessage(
        from message: ChatMessage,
        profile: ContextBudgetProfile
    ) -> ContextMessage? {
        guard isEligible(message, profile: profile) else { return nil }

        let text: String
        switch message.role {
        case .user:
            text = message.text
        case .assistant:
            guard profile.includeAssistantMessages else { return nil }
            text = ContextHistorySanitizer.cleanAssistantText(message.text)
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return ContextMessage(
            id: message.id,
            role: message.role,
            text: text,
            replyToMessageId: message.replyToMessageId
        )
    }

    private func isEligible(_ message: ChatMessage, profile: ContextBudgetProfile) -> Bool {
        switch message.deliveryState {
        case .delivered:
            return true
        case .failed, .cancelled:
            return profile.includeFailedMessages
        case .pending:
            return false
        }
    }

    private func pruneMessageCount(
        in messages: inout [ContextMessage],
        maxMessages: Int,
        protectedMessageIds: Set<UUID>
    ) {
        while messages.count > maxMessages {
            guard let removalIndex = removalIndex(in: messages, protectedMessageIds: protectedMessageIds) else {
                break
            }
            messages.remove(at: removalIndex)
        }
    }

    private func pruneCharacterCount(
        in messages: inout [ContextMessage],
        maxCharacters: Int,
        protectedMessageIds: Set<UUID>
    ) {
        while characterCount(messages) > maxCharacters {
            if let removalIndex = removalIndex(in: messages, protectedMessageIds: protectedMessageIds) {
                messages.remove(at: removalIndex)
                continue
            }

            guard let protectedIndex = messages.firstIndex(where: { protectedMessageIds.contains($0.id) }) else {
                messages.removeAll()
                return
            }

            messages[protectedIndex] = ContextMessage(
                id: messages[protectedIndex].id,
                role: messages[protectedIndex].role,
                text: truncate(messages[protectedIndex].text, to: maxCharacters),
                replyToMessageId: messages[protectedIndex].replyToMessageId
            )
            return
        }
    }

    private func removalIndex(
        in messages: [ContextMessage],
        protectedMessageIds: Set<UUID>
    ) -> Int? {
        if let assistantIndex = messages.firstIndex(where: {
            $0.role == .assistant && !protectedMessageIds.contains($0.id)
        }) {
            return assistantIndex
        }

        return messages.firstIndex(where: { !protectedMessageIds.contains($0.id) })
    }

    private func characterCount(_ messages: [ContextMessage]) -> Int {
        messages.reduce(0) { $0 + $1.text.count }
    }

    private func truncate(_ text: String, to maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters))
    }
}

private enum ContextHistorySanitizer {
    static func cleanAssistantText(_ text: String) -> String {
        let withoutClosedThinking = replacingMatches(
            in: text,
            pattern: "(?is)<think>.*?</think>",
            with: ""
        )
        let withoutOpenThinking = replacingMatches(
            in: withoutClosedThinking,
            pattern: "(?is)<think>.*$",
            with: ""
        )

        let stopTokens = [
            "<end_of_turn>",
            "<|end_of_turn|>",
            "<|im_end|>",
            "<|endoftext|>",
            "<|eot_id|>",
            "<|end|>",
            "</s>"
        ]

        let cleaned = stopTokens.reduce(withoutOpenThinking) { partial, token in
            partial.replacingOccurrences(of: token, with: "")
        }

        return cleaned
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        with template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
