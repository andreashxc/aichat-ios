import Foundation

struct LocalGenerationProfile: Hashable, Sendable {
    let temperature: Double
    let maxTokens: Int
    let topP: Double
    let topK: Int
    let presencePenalty: Double
    let thinkingMode: LocalThinkingModePreference

    static func from(request: ChatRequest) -> LocalGenerationProfile {
        LocalGenerationProfile(
            temperature: request.settings.temperature,
            maxTokens: request.settings.maxTokens ?? 512,
            topP: 0.9,
            topK: 40,
            presencePenalty: 0,
            thinkingMode: ModelPreferences.localThinkingMode
        )
    }
}

struct LocalGenerationOptions: Hashable, Sendable {
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let topK: Int
    let stopTokens: [String]

    init(profile: LocalGenerationProfile, stopTokens: [String]) {
        self.maxTokens = max(1, profile.maxTokens)
        self.temperature = Float(profile.temperature)
        self.topP = Float(profile.topP)
        self.topK = profile.topK
        self.stopTokens = stopTokens
    }
}

enum LocalPromptBackend: Hashable, Sendable {
    case mlx
    case swiftLlama
}

enum LocalSwiftLlamaPromptKind: Hashable, Sendable {
    case chatML
    case llama
    case llama3
    case mistral
    case phi
    case gemma
}

struct LocalPromptTurn: Hashable, Sendable {
    let user: String
    let assistant: String
}

struct LocalSwiftLlamaPrompt: Hashable, Sendable {
    let kind: LocalSwiftLlamaPromptKind
    let systemPrompt: String
    let userMessage: String
    let history: [LocalPromptTurn]
}

struct LocalRenderedPrompt: Hashable, Sendable {
    let backend: LocalPromptBackend
    let text: String
    let swiftLlamaPrompt: LocalSwiftLlamaPrompt?
    let options: LocalGenerationOptions
}

protocol LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt

    func sanitizeResponse(_ response: String) -> String
}

enum LocalPromptRendererFactory {
    static func makeRenderer(for definition: LocalModelDefinition) -> LocalPromptRenderer {
        let id = definition.id.lowercased()
        let familyId = definition.familyId.lowercased()
        let name = definition.familyName.lowercased()

        if familyId.contains("qwen-3") || id.hasPrefix("qwen3") {
            return Qwen3Renderer()
        }
        if familyId.contains("qwen-2.5") || id.hasPrefix("qwen-2.5") {
            return Qwen2_5Renderer()
        }
        if id.contains("gemma-3") {
            return Gemma3Renderer()
        }
        if familyId.contains("gemma") || id.contains("gemma") {
            return Gemma2Renderer()
        }
        if familyId.contains("mistral") || name.contains("mistral") || id.contains("mistral") || id.contains("mixtral") {
            return MistralRenderer()
        }
        return GenericLlamaRenderer()
    }
}

struct Qwen2_5Renderer: LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt {
        let transcript = PromptTranscript.from(request: request)
        let prompt = QwenChatMLTemplate.render(transcript: transcript)
        return LocalRenderedPrompt(
            backend: backend,
            text: prompt,
            swiftLlamaPrompt: SwiftLlamaPromptBuilder.qwenChatMLPrompt(from: transcript),
            options: LocalGenerationOptions(profile: profile, stopTokens: ["<|im_end|>", "<|endoftext|>"])
        )
    }

    func sanitizeResponse(_ response: String) -> String {
        LocalResponseSanitizer.clean(response)
    }
}

struct Qwen3Renderer: LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt {
        var transcript = PromptTranscript.from(request: request)
        transcript.systemPrompt = mergeSystemPrompt(
            transcript.systemPrompt,
            thinkingInstruction(for: profile.thinkingMode)
        )

        if transcript.systemPrompt?.isEmpty == false {
            transcript.systemPrompt = "\(transcript.systemPrompt!)\n\n\(thinkingSwitch(for: profile.thinkingMode))"
        } else {
            transcript.userMessage = "\(transcript.userMessage)\n\n\(thinkingSwitch(for: profile.thinkingMode))"
        }

        let prompt = QwenChatMLTemplate.render(transcript: transcript)
        return LocalRenderedPrompt(
            backend: backend,
            text: prompt,
            swiftLlamaPrompt: SwiftLlamaPromptBuilder.qwenChatMLPrompt(from: transcript),
            options: LocalGenerationOptions(profile: qwen3Profile(profile), stopTokens: ["<|im_end|>", "<|endoftext|>"])
        )
    }

    func sanitizeResponse(_ response: String) -> String {
        LocalResponseSanitizer.clean(response)
    }

    private func thinkingInstruction(for mode: LocalThinkingModePreference) -> String {
        switch mode {
        case .off:
            return "Reason internally only when necessary, and never expose hidden reasoning."
        case .automatic:
            return "Choose between concise answering and deeper internal reasoning as needed, but do not expose hidden reasoning."
        case .on:
            return "You may reason internally for hard tasks, but do not expose hidden reasoning."
        }
    }

    private func thinkingSwitch(for mode: LocalThinkingModePreference) -> String {
        switch mode {
        case .off:
            return "/no_think"
        case .automatic:
            return "/no_think"
        case .on:
            return "/think"
        }
    }

    private func qwen3Profile(_ profile: LocalGenerationProfile) -> LocalGenerationProfile {
        LocalGenerationProfile(
            temperature: profile.temperature,
            maxTokens: profile.maxTokens,
            topP: profile.thinkingMode == .on ? 0.95 : profile.topP,
            topK: profile.thinkingMode == .on ? 20 : profile.topK,
            presencePenalty: profile.presencePenalty,
            thinkingMode: profile.thinkingMode
        )
    }
}

struct Gemma2Renderer: LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt {
        let transcript = PromptTranscript.from(request: request)
        let prompt = GemmaTemplate.render(transcript: transcript, includeBOS: true)
        return LocalRenderedPrompt(
            backend: backend,
            text: prompt,
            swiftLlamaPrompt: SwiftLlamaPromptBuilder.gemmaPrompt(from: transcript),
            options: LocalGenerationOptions(profile: profile, stopTokens: ["<end_of_turn>", "<eos>", "</s>"])
        )
    }

    func sanitizeResponse(_ response: String) -> String {
        LocalResponseSanitizer.clean(response)
    }
}

struct Gemma3Renderer: LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt {
        let transcript = PromptTranscript.from(request: request)
        let prompt = GemmaTemplate.render(transcript: transcript, includeBOS: true)
        return LocalRenderedPrompt(
            backend: backend,
            text: prompt,
            swiftLlamaPrompt: SwiftLlamaPromptBuilder.gemmaPrompt(from: transcript),
            options: LocalGenerationOptions(profile: profile, stopTokens: ["<end_of_turn>", "<eos>", "</s>"])
        )
    }

    func sanitizeResponse(_ response: String) -> String {
        LocalResponseSanitizer.clean(response)
    }
}

struct MistralRenderer: LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt {
        let transcript = PromptTranscript.from(request: request)
        let prompt = MistralTemplate.render(transcript: transcript)
        return LocalRenderedPrompt(
            backend: backend,
            text: prompt,
            swiftLlamaPrompt: SwiftLlamaPromptBuilder.mistralPrompt(from: transcript),
            options: LocalGenerationOptions(profile: profile, stopTokens: ["</s>"])
        )
    }

    func sanitizeResponse(_ response: String) -> String {
        LocalResponseSanitizer.clean(response)
    }
}

struct GenericLlamaRenderer: LocalPromptRenderer {
    func render(
        request: ChatRequest,
        profile: LocalGenerationProfile,
        backend: LocalPromptBackend
    ) -> LocalRenderedPrompt {
        let transcript = PromptTranscript.from(request: request)
        let prompt = Llama3Template.render(transcript: transcript)
        return LocalRenderedPrompt(
            backend: backend,
            text: prompt,
            swiftLlamaPrompt: SwiftLlamaPromptBuilder.llama3Prompt(from: transcript),
            options: LocalGenerationOptions(profile: profile, stopTokens: ["<|eot_id|>", "</s>"])
        )
    }

    func sanitizeResponse(_ response: String) -> String {
        LocalResponseSanitizer.clean(response)
    }
}

private struct PromptMessage: Hashable, Sendable {
    let role: MessageRole
    let text: String
}

private struct PromptTranscript: Hashable, Sendable {
    var systemPrompt: String?
    var history: [PromptMessage]
    var userMessage: String

    static func from(request: ChatRequest) -> PromptTranscript {
        PromptTranscript(
            systemPrompt: sanitized(request.systemPrompt),
            history: request.contextMessages.compactMap { message in
                guard let text = sanitized(message.text), !text.isEmpty else { return nil }
                return PromptMessage(role: message.role, text: text)
            },
            userMessage: sanitized(request.userMessageText) ?? ""
        )
    }

    private static func sanitized(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = LocalResponseSanitizer.cleanHistoryText(text)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private enum QwenChatMLTemplate {
    static func render(transcript: PromptTranscript) -> String {
        var prompt = ""
        if let systemPrompt = transcript.systemPrompt, !systemPrompt.isEmpty {
            prompt += "<|im_start|>system\n\(systemPrompt)<|im_end|>\n"
        }

        for message in transcript.history {
            prompt += "<|im_start|>\(roleName(message.role))\n\(message.text)<|im_end|>\n"
        }

        prompt += "<|im_start|>user\n\(transcript.userMessage)<|im_end|>\n"
        prompt += "<|im_start|>assistant\n"
        return prompt
    }

    private static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }
}

private enum GemmaTemplate {
    static func render(transcript: PromptTranscript, includeBOS: Bool) -> String {
        var prompt = includeBOS ? "<bos>" : ""

        for message in transcript.history {
            prompt += "<start_of_turn>\(roleName(message.role))\n\(message.text)<end_of_turn>\n"
        }

        let userMessage = [transcript.systemPrompt, transcript.userMessage]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")

        prompt += "<start_of_turn>user\n\(userMessage)<end_of_turn>\n"
        prompt += "<start_of_turn>model\n"
        return prompt
    }

    private static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "model"
        }
    }
}

private enum MistralTemplate {
    static func render(transcript: PromptTranscript) -> String {
        var prompt = "<s>"
        if let systemPrompt = transcript.systemPrompt, !systemPrompt.isEmpty {
            prompt += "[INST] \(systemPrompt) [/INST]</s>"
        }

        for pair in ConversationPairs.from(transcript.history) {
            prompt += "[INST] \(pair.user) [/INST] \(pair.assistant)</s>"
        }

        prompt += "[INST] \(transcript.userMessage) [/INST]"
        return prompt
    }
}

private enum Llama3Template {
    static func render(transcript: PromptTranscript) -> String {
        var prompt = ""
        if let systemPrompt = transcript.systemPrompt, !systemPrompt.isEmpty {
            prompt += "<|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
        }

        for message in transcript.history {
            prompt += "<|start_header_id|>\(roleName(message.role))<|end_header_id|>\n\n\(message.text)<|eot_id|>"
        }

        prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(transcript.userMessage)<|eot_id|>"
        prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n"
        return prompt
    }

    private static func roleName(_ role: MessageRole) -> String {
        switch role {
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }
}

private enum SwiftLlamaPromptBuilder {
    static func qwenChatMLPrompt(from transcript: PromptTranscript) -> LocalSwiftLlamaPrompt {
        LocalSwiftLlamaPrompt(
            kind: .chatML,
            systemPrompt: transcript.systemPrompt ?? "",
            userMessage: transcript.userMessage,
            history: ConversationPairs.from(transcript.history)
        )
    }

    static func gemmaPrompt(from transcript: PromptTranscript) -> LocalSwiftLlamaPrompt {
        let userMessage = [transcript.systemPrompt, transcript.userMessage]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n\n")

        return LocalSwiftLlamaPrompt(
            kind: .gemma,
            systemPrompt: "",
            userMessage: userMessage,
            history: ConversationPairs.from(transcript.history)
        )
    }

    static func mistralPrompt(from transcript: PromptTranscript) -> LocalSwiftLlamaPrompt {
        LocalSwiftLlamaPrompt(
            kind: .mistral,
            systemPrompt: transcript.systemPrompt ?? "",
            userMessage: transcript.userMessage,
            history: ConversationPairs.from(transcript.history)
        )
    }

    static func llama3Prompt(from transcript: PromptTranscript) -> LocalSwiftLlamaPrompt {
        LocalSwiftLlamaPrompt(
            kind: .llama3,
            systemPrompt: transcript.systemPrompt ?? "",
            userMessage: transcript.userMessage,
            history: ConversationPairs.from(transcript.history)
        )
    }
}

private enum ConversationPairs {
    static func from(_ messages: [PromptMessage]) -> [LocalPromptTurn] {
        var pairs: [LocalPromptTurn] = []
        var pendingUser: String?

        for message in messages {
            switch message.role {
            case .user:
                pendingUser = message.text
            case .assistant:
                if let user = pendingUser, !message.text.isEmpty {
                    pairs.append(LocalPromptTurn(user: user, assistant: message.text))
                    pendingUser = nil
                }
            }
        }

        return pairs
    }
}

private func mergeSystemPrompt(_ prompt: String?, _ addition: String) -> String {
    [prompt, addition]
        .compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .joined(separator: "\n\n")
}

enum LocalResponseSanitizer {
    static func clean(_ response: String) -> String {
        let withoutThinking = stripThinkTags(from: response)
        let artifacts = [
            "<end_of_turn>",
            "<|end_of_turn|>",
            "<|im_end|>",
            "<|endoftext|>",
            "<|eot_id|>",
            "<|end|>",
            "<eos>",
            "</s>"
        ]

        let withoutArtifacts = artifacts.reduce(withoutThinking) { partial, artifact in
            partial.replacingOccurrences(of: artifact, with: "")
        }

        return removeDuplicatedAssistantPrefix(from: withoutArtifacts)
            .replacingOccurrences(of: "</think>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanHistoryText(_ text: String) -> String {
        clean(text)
    }

    private static func stripThinkTags(from text: String) -> String {
        let withoutClosedTags = replacingMatches(
            in: text,
            pattern: "(?is)<think>.*?</think>",
            with: ""
        )

        return replacingMatches(
            in: withoutClosedTags,
            pattern: "(?is)<think>.*$",
            with: ""
        )
    }

    private static func removeDuplicatedAssistantPrefix(from text: String) -> String {
        replacingMatches(
            in: text,
            pattern: #"(?is)^\s*(?:"?<\|im_start\|>assistant"?|assistant|model)\s*:?\s*"#,
            with: ""
        )
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

struct LocalStopTokenStreamFilter: Sendable {
    private let stopTokens: [String]
    private let maxStopTokenLength: Int
    private var buffer = ""

    init(stopTokens: [String]) {
        self.stopTokens = stopTokens.filter { !$0.isEmpty }
        self.maxStopTokenLength = self.stopTokens.map(\.count).max() ?? 0
    }

    mutating func consume(_ chunk: String) -> (output: String, didStop: Bool) {
        guard !stopTokens.isEmpty else {
            return (chunk, false)
        }

        buffer += chunk
        if let match = firstStopTokenRange(in: buffer) {
            let output = String(buffer[..<match.lowerBound])
            buffer = ""
            return (output, true)
        }

        let retainedSuffixLength = max(0, maxStopTokenLength - 1)
        guard buffer.count > retainedSuffixLength else {
            return ("", false)
        }

        let outputEnd = buffer.index(buffer.endIndex, offsetBy: -retainedSuffixLength)
        let output = String(buffer[..<outputEnd])
        buffer = String(buffer[outputEnd...])
        return (output, false)
    }

    mutating func finish() -> String {
        defer { buffer = "" }
        return buffer
    }

    private func firstStopTokenRange(in text: String) -> Range<String.Index>? {
        stopTokens
            .compactMap { text.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
    }
}
