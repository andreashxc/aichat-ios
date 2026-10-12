import SwiftData
import XCTest
@testable import AiChat

@MainActor
final class ChatViewModelGenerationTests: XCTestCase {
    func testNormalStreamingResponseCreatesOneAssistantMessage() async throws {
        let provider = FakeStreamingLocalProvider(tokens: ["Hello", " there", "."])
        let viewModel = try makeViewModel(provider: provider)

        viewModel.composerText = "Say hello"
        viewModel.sendMessage()

        try await waitUntil {
            self.assistantMessages(in: viewModel).first?.deliveryState == .delivered
        }

        let assistantMessages = assistantMessages(in: viewModel)
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.text, "Hello there.")
        XCTAssertEqual(assistantMessages.first?.deliveryState, .delivered)
    }

    func testCancellationDoesNotCreateDuplicateAssistantMessages() async throws {
        let provider = FakeStreamingLocalProvider(
            tokens: ["partial", " response"],
            delayAfterTokenNanoseconds: 1_000_000_000
        )
        let viewModel = try makeViewModel(provider: provider)

        viewModel.composerText = "Start then cancel"
        viewModel.sendMessage()

        try await waitUntil {
            self.assistantMessages(in: viewModel).first?.text == "partial"
        }

        viewModel.cancelGeneration()

        try await waitUntil {
            self.assistantMessages(in: viewModel).first?.deliveryState == .cancelled
        }

        let assistantMessages = assistantMessages(in: viewModel)
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.text, "partial")
        XCTAssertEqual(assistantMessages.first?.deliveryState, .cancelled)
    }

    func testErrorUpdatesOneAssistantMessage() async throws {
        let provider = FakeStreamingLocalProvider(error: TestStreamingError.boom)
        let viewModel = try makeViewModel(provider: provider)

        viewModel.composerText = "Fail"
        viewModel.sendMessage()

        try await waitUntil {
            self.assistantMessages(in: viewModel).first?.deliveryState == .failed
        }

        let assistantMessages = assistantMessages(in: viewModel)
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.deliveryState, .failed)
        XCTAssertTrue(assistantMessages.first?.text.contains("Local error") == true)
    }

    func testLongParagraphResponseDoesNotCreateParagraphMessageRows() async throws {
        let response = """
        First paragraph.

        Second paragraph.

        - Bullet one
        - Bullet two
        """
        let provider = FakeStreamingLocalProvider(tokens: [response])
        let viewModel = try makeViewModel(provider: provider)

        viewModel.composerText = "Give me paragraphs"
        viewModel.sendMessage()

        try await waitUntil {
            self.assistantMessages(in: viewModel).first?.deliveryState == .delivered
        }

        let assistantMessages = assistantMessages(in: viewModel)
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.text, response)
        XCTAssertGreaterThan(ParagraphDeliveryPipeline.splitText(response).count, 1)
    }

    private func makeViewModel(provider: FakeStreamingLocalProvider) throws -> ChatViewModel {
        let container = try ModelContainer(
            for: Conversation.self,
            ChatMessage.self,
            LocalModelDescriptor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let environment = AppEnvironment(
            modelContainer: container,
            providerConfig: ProviderConfig(activeProvider: .local, localModel: "fake-local-model"),
            localProvider: provider
        )
        return ChatViewModel(environment: environment)
    }

    private func assistantMessages(in viewModel: ChatViewModel) -> [ChatMessage] {
        viewModel.messages.filter { $0.role == .assistant }
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor
private final class FakeStreamingLocalProvider: LocalProviding {
    let id: ProviderID = .local
    let displayName = "Fake Local"

    private let tokens: [String]
    private let delayAfterTokenNanoseconds: UInt64
    private let error: Error?

    init(
        tokens: [String] = [],
        delayAfterTokenNanoseconds: UInt64 = 0,
        error: Error? = nil
    ) {
        self.tokens = tokens
        self.delayAfterTokenNanoseconds = delayAfterTokenNanoseconds
        self.error = error
    }

    func generate(request: ChatRequest) async throws -> String {
        tokens.joined()
    }

    func generateStreaming(
        request: ChatRequest,
        onToken: @escaping (String) -> Void
    ) async throws {
        if let error {
            throw error
        }

        for token in tokens {
            try Task.checkCancellation()
            onToken(token)
            if delayAfterTokenNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayAfterTokenNanoseconds)
            }
        }
    }

    func supportsModels() -> Bool {
        true
    }

    func availableModels() async -> [ModelInfo] {
        []
    }

    func loadModel(modelName: String) async throws {}

    func cleanup() async {}

    var providerStatus: String {
        get async { "Fake provider ready" }
    }

    var runtimeStatus: LocalRuntimeStatus {
        get async { .idle }
    }
}

private enum TestStreamingError: LocalizedError {
    case boom

    var errorDescription: String? {
        "Local error"
    }
}
