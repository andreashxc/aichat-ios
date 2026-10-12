import XCTest
@testable import AiChat

final class LocalPromptRendererTests: XCTestCase {
    private let conversationId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testQwen25MLXPromptSnapshot() throws {
        let definition = syntheticDefinition(id: "qwen-2.5-3b", familyId: "qwen-2.5", familyName: "Qwen 2.5")
        let prompt = render(definition: definition, backend: .mlx).text

        XCTAssertEqual(
            prompt,
            """
            <|im_start|>system
            Be concise.<|im_end|>
            <|im_start|>user
            Hello<|im_end|>
            <|im_start|>assistant
            Hi there<|im_end|>
            <|im_start|>user
            Next question<|im_end|>
            <|im_start|>assistant

            """
        )
    }

    func testQwen3PromptSnapshotAndThinkingHistorySanitization() throws {
        let definition = try XCTUnwrap(LocalModelRegistry.shared.definition(for: "qwen3-1.7b", includeExperimental: true))
        let prompt = render(definition: definition, backend: .mlx, thinkingMode: .off).text

        XCTAssertEqual(
            prompt,
            """
            <|im_start|>system
            Be concise.

            Reason internally only when necessary, and never expose hidden reasoning.

            /no_think<|im_end|>
            <|im_start|>user
            Hello<|im_end|>
            <|im_start|>assistant
            Hi there<|im_end|>
            <|im_start|>user
            Next question<|im_end|>
            <|im_start|>assistant

            """
        )
        XCTAssertFalse(prompt.contains("<think>hidden</think>"))
    }

    func testQwen3SwiftLlamaFieldsAvoidChatMLRoundTrip() throws {
        let definition = try XCTUnwrap(LocalModelRegistry.shared.definition(for: "qwen3-1.7b", includeExperimental: true))
        let rendered = render(definition: definition, backend: .swiftLlama, thinkingMode: .off)

        XCTAssertEqual(rendered.swiftLlamaPrompt?.kind, .chatML)
        XCTAssertEqual(rendered.swiftLlamaPrompt?.userMessage, "Next question")
        XCTAssertEqual(rendered.swiftLlamaPrompt?.history, [LocalPromptTurn(user: "Hello", assistant: "Hi there")])
        XCTAssertEqual(rendered.options.stopTokens, ["<|im_end|>", "<|endoftext|>"])
    }

    func testGemma2PromptSnapshot() throws {
        let definition = syntheticDefinition(id: "gemma-2-2b", familyId: "gemma", familyName: "Gemma")
        let rendered = render(definition: definition, backend: .swiftLlama)

        XCTAssertEqual(
            rendered.text,
            """
            <bos><start_of_turn>user
            Hello<end_of_turn>
            <start_of_turn>model
            Hi there<end_of_turn>
            <start_of_turn>user
            Be concise.

            Next question<end_of_turn>
            <start_of_turn>model

            """
        )
        XCTAssertEqual(rendered.swiftLlamaPrompt?.kind, .gemma)
        XCTAssertEqual(rendered.swiftLlamaPrompt?.systemPrompt, "")
        XCTAssertEqual(rendered.swiftLlamaPrompt?.userMessage, "Be concise.\n\nNext question")
    }

    func testGemma3PromptSnapshot() throws {
        let definition = syntheticDefinition(id: "gemma-3-1b", familyId: "gemma", familyName: "Gemma")
        let rendered = render(definition: definition, backend: .mlx)

        XCTAssertEqual(
            rendered.text,
            """
            <bos><start_of_turn>user
            Hello<end_of_turn>
            <start_of_turn>model
            Hi there<end_of_turn>
            <start_of_turn>user
            Be concise.

            Next question<end_of_turn>
            <start_of_turn>model

            """
        )
    }

    func testMistralPromptSnapshot() {
        let rendered = render(definition: syntheticDefinition(id: "mistral-7b", familyId: "mistral", familyName: "Mistral"), backend: .swiftLlama)

        XCTAssertEqual(rendered.text, "<s>[INST] Be concise. [/INST]</s>[INST] Hello [/INST] Hi there</s>[INST] Next question [/INST]")
        XCTAssertEqual(rendered.swiftLlamaPrompt?.kind, .mistral)
    }

    func testGenericLlamaPromptSnapshot() {
        let rendered = render(definition: syntheticDefinition(id: "llama-3.2-3b", familyId: "llama", familyName: "Llama"), backend: .swiftLlama)

        XCTAssertEqual(
            rendered.text,
            """
            <|start_header_id|>system<|end_header_id|>

            Be concise.<|eot_id|><|start_header_id|>user<|end_header_id|>

            Hello<|eot_id|><|start_header_id|>assistant<|end_header_id|>

            Hi there<|eot_id|><|start_header_id|>user<|end_header_id|>

            Next question<|eot_id|><|start_header_id|>assistant<|end_header_id|>

            """
        )
        XCTAssertEqual(rendered.swiftLlamaPrompt?.kind, .llama3)
    }

    func testGenerationOptionsAreRenderedWithPrompt() throws {
        let definition = syntheticDefinition(id: "qwen-2.5-3b", familyId: "qwen-2.5", familyName: "Qwen 2.5")
        let request = makeRequest(settings: GenerationSettings(temperature: 0.42, maxTokens: 123, model: definition.id))
        let profile = LocalGenerationProfile(
            temperature: request.settings.temperature,
            maxTokens: request.settings.maxTokens ?? 512,
            topP: 0.77,
            topK: 12,
            presencePenalty: 0,
            thinkingMode: .automatic
        )

        let rendered = LocalPromptRendererFactory.makeRenderer(for: definition)
            .render(request: request, profile: profile, backend: .mlx)

        XCTAssertEqual(rendered.options.maxTokens, 123)
        XCTAssertEqual(rendered.options.temperature, 0.42, accuracy: 0.0001)
        XCTAssertEqual(rendered.options.topP, 0.77, accuracy: 0.0001)
        XCTAssertEqual(rendered.options.topK, 12)
    }

    func testResponseSanitizerRemovesThinkTags() {
        XCTAssertEqual(LocalResponseSanitizer.clean("<think>secret</think>Hello"), "Hello")
        XCTAssertEqual(LocalResponseSanitizer.clean("<think>unfinished\nhidden"), "")
    }

    func testResponseSanitizerRemovesStopTokens() {
        XCTAssertEqual(LocalResponseSanitizer.clean("Hello<|im_end|><|eot_id|></s>"), "Hello")
    }

    func testResponseSanitizerRemovesDuplicatedAssistantPrefix() {
        XCTAssertEqual(LocalResponseSanitizer.clean("<|im_start|>assistant\nHello"), "Hello")
        XCTAssertEqual(LocalResponseSanitizer.clean("assistant: Hello"), "Hello")
        XCTAssertEqual(LocalResponseSanitizer.clean("model\nHello"), "Hello")
    }

    func testResponseSanitizerHandlesEmptyOutput() {
        XCTAssertEqual(LocalResponseSanitizer.clean("  <|im_end|>\n"), "")
    }

    func testStopTokenStreamFilterHandlesSplitStopToken() {
        var filter = LocalStopTokenStreamFilter(stopTokens: ["<|im_end|>"])

        XCTAssertEqual(filter.consume("Hel").output, "")
        XCTAssertEqual(filter.consume("lo<|im").output, "H")
        let stopped = filter.consume("_end|>ignored")
        XCTAssertEqual(stopped.output, "ello")
        XCTAssertTrue(stopped.didStop)
        XCTAssertEqual(filter.finish(), "")
    }

    private func render(
        definition: LocalModelDefinition,
        backend: LocalPromptBackend,
        thinkingMode: LocalThinkingModePreference = .automatic
    ) -> LocalRenderedPrompt {
        let request = makeRequest(settings: GenerationSettings(model: definition.id))
        let profile = LocalGenerationProfile(
            temperature: 0.7,
            maxTokens: 256,
            topP: 0.9,
            topK: 40,
            presencePenalty: 0,
            thinkingMode: thinkingMode
        )
        return LocalPromptRendererFactory.makeRenderer(for: definition)
            .render(request: request, profile: profile, backend: backend)
    }

    private func makeRequest(settings: GenerationSettings) -> ChatRequest {
        ChatRequest(
            conversationId: conversationId,
            userMessageText: "Next question",
            contextMessages: [
                ContextMessage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, role: .user, text: "Hello", replyToMessageId: nil),
                ContextMessage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, role: .assistant, text: "<think>hidden</think>Hi there<|im_end|>", replyToMessageId: nil)
            ],
            settings: settings,
            systemPrompt: "Be concise."
        )
    }

    private func syntheticDefinition(id: String, familyId: String, familyName: String) -> LocalModelDefinition {
        LocalModelDefinition(
            id: id,
            familyId: familyId,
            familyName: familyName,
            icon: "test",
            displayName: id,
            description: "Synthetic test definition",
            tags: [],
            capabilities: [.text],
            highlights: [],
            variants: [
                LocalModelVariant(
                    id: "\(id)-gguf",
                    definitionId: id,
                    backend: .llama,
                    artifactFormat: .gguf,
                    quantization: "Q4",
                    minimumIOSVersion: 18,
                    minimumRAMGB: 6,
                    preferredDevices: [],
                    downloadSource: .direct(url: "https://example.com/model.gguf"),
                    sizeGB: 1,
                    sizeMB: 1024,
                    isExperimental: false,
                    minimumDeviceDescription: "test"
                )
            ]
        )
    }
}
