import Foundation

struct FoundationPromptBuilder {
    struct PromptComponents {
        let systemInstructions: String
        let body: String
    }

    static func buildPrompt(
        context: [ContextMessage],
        userMessage: String,
        targetMessage: String? = nil,
        systemPrompt: String? = nil
    ) -> PromptComponents {
        let toneInstruction = """
        You are a concise on-device assistant. Respond in clear prose with blank lines between paragraphs. Avoid markdown unless explicitly requested. Avoid emoji unless asked.
        """
        let trimmedSystemPrompt = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let systemInstructions = trimmedSystemPrompt.isEmpty ? toneInstruction : trimmedSystemPrompt

        var lines: [String] = []
        if let targetMessage, !targetMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Reference message: \(targetMessage)")
        }

        for message in context {
            let prefix = message.role == .user ? "User" : "Assistant"
            lines.append("\(prefix): \(message.text)")
        }

        lines.append("User: \(userMessage)")

        let body = lines.joined(separator: "\n")
        return PromptComponents(
            systemInstructions: systemInstructions,
            body: body
        )
    }
}
