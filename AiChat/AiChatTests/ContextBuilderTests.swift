import XCTest
@testable import AiChat

final class ContextBudgeterTests: XCTestCase {
    func testLongChatIsTruncated() {
        let conversationId = UUID()
        let messages = (0..<12).map { index in
            ChatMessage(
                conversationId: conversationId,
                role: index.isMultiple(of: 2) ? .user : .assistant,
                text: "message-\(index)-" + String(repeating: "x", count: 20),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                deliveryState: .delivered,
                sourceProvider: .local
            )
        }

        let budgeter = ContextBudgeter()
        let profile = ContextBudgetProfile(
            providerId: .local,
            modelId: "qwen3-1.7b",
            maxCharacters: 90,
            maxMessages: 4,
            preserveSystemPrompt: true,
            preserveLastUserMessage: true,
            includeAssistantMessages: true
        )

        let context = budgeter.makeContext(messages: messages, profile: profile)

        XCTAssertLessThanOrEqual(context.count, 4)
        XCTAssertLessThanOrEqual(context.reduce(0) { $0 + $1.text.count }, 90)
        XCTAssertLessThan(context.count, messages.count)
    }

    func testLatestUserMessageIsPreserved() {
        let conversationId = UUID()
        let oldUser = makeMessage(
            conversationId: conversationId,
            role: .user,
            text: "Old question",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceProvider: .local
        )
        let assistant = makeMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "Old answer",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceProvider: .local
        )
        let latestUser = makeMessage(
            conversationId: conversationId,
            role: .user,
            text: "Latest question",
            createdAt: Date(timeIntervalSince1970: 3),
            sourceProvider: .local
        )

        let context = ContextBudgeter().makeContext(
            messages: [oldUser, assistant, latestUser],
            profile: ContextBudgetProfile(
                providerId: .local,
                modelId: "qwen3.5-2b",
                maxCharacters: 100,
                maxMessages: 1,
                preserveSystemPrompt: true,
                preserveLastUserMessage: true,
                includeAssistantMessages: true
            )
        )

        XCTAssertEqual(context.map(\.id), [latestUser.id])
        XCTAssertEqual(context.first?.text, "Latest question")
    }

    func testOldAssistantMessagesAreDroppedFirstWhenBudgetIsTight() {
        let conversationId = UUID()
        let oldUser = makeMessage(
            conversationId: conversationId,
            role: .user,
            text: "Old question",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceProvider: .local
        )
        let oldAssistant = makeMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "Old answer",
            createdAt: Date(timeIntervalSince1970: 2),
            sourceProvider: .local
        )
        let middleUser = makeMessage(
            conversationId: conversationId,
            role: .user,
            text: "Middle question",
            createdAt: Date(timeIntervalSince1970: 3),
            sourceProvider: .local
        )
        let latestUser = makeMessage(
            conversationId: conversationId,
            role: .user,
            text: "Latest question",
            createdAt: Date(timeIntervalSince1970: 4),
            sourceProvider: .local
        )

        let context = ContextBudgeter().makeContext(
            messages: [oldUser, oldAssistant, middleUser, latestUser],
            profile: ContextBudgetProfile(
                providerId: .local,
                modelId: "qwen3-1.7b",
                maxCharacters: 1_000,
                maxMessages: 3,
                preserveSystemPrompt: true,
                preserveLastUserMessage: true,
                includeAssistantMessages: true
            )
        )

        XCTAssertTrue(context.contains(where: { $0.id == oldUser.id }))
        XCTAssertFalse(context.contains(where: { $0.id == oldAssistant.id }))
        XCTAssertEqual(context.map(\.id), [oldUser.id, middleUser.id, latestUser.id])
    }

    func testFailedAndCancelledMessagesAreExcluded() {
        let conversationId = UUID()
        let deliveredAssistant = ChatMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "Delivered answer",
            deliveryState: .delivered,
            sourceProvider: .openAI
        )

        let pendingAssistant = ChatMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "Pending answer",
            deliveryState: .pending,
            sourceProvider: .openAI
        )

        let failedAssistant = ChatMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "Local error: failed",
            deliveryState: .failed,
            sourceProvider: .local
        )

        let cancelledAssistant = ChatMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "Partial cancelled answer",
            deliveryState: .cancelled,
            sourceProvider: .local
        )

        let userMessage = ChatMessage(
            conversationId: conversationId,
            role: .user,
            text: "Question",
            deliveryState: .delivered,
            sourceProvider: .openAI
        )

        let context = ContextBudgeter().makeContext(
            messages: [deliveredAssistant, pendingAssistant, failedAssistant, cancelledAssistant, userMessage],
            profile: ContextBudgetProfile.foundationModels(modelId: nil)
        )

        XCTAssertEqual(context.count, 2)
        XCTAssertTrue(context.contains(where: { $0.text == deliveredAssistant.text }))
        XCTAssertTrue(context.contains(where: { $0.text == userMessage.text }))
        XCTAssertFalse(context.contains(where: { $0.text == pendingAssistant.text }))
        XCTAssertFalse(context.contains(where: { $0.text == failedAssistant.text }))
        XCTAssertFalse(context.contains(where: { $0.text == cancelledAssistant.text }))
    }

    func testQwenThinkingTagsAndStopTokensAreStrippedFromAssistantHistory() {
        let conversationId = UUID()
        let assistant = makeMessage(
            conversationId: conversationId,
            role: .assistant,
            text: "<think>hidden reasoning</think>Visible answer<|im_end|>",
            sourceProvider: .local
        )
        let user = makeMessage(
            conversationId: conversationId,
            role: .user,
            text: "Next question",
            createdAt: Date(timeIntervalSince1970: 1),
            sourceProvider: .local
        )

        let context = ContextBudgeter().makeContext(
            messages: [assistant, user],
            profile: ContextBudgetProfile.localSmall(modelId: "qwen3-1.7b")
        )

        XCTAssertEqual(context.first(where: { $0.role == .assistant })?.text, "Visible answer")
        XCTAssertFalse(context.contains(where: { $0.text.contains("<think>") }))
        XCTAssertFalse(context.contains(where: { $0.text.contains("<|im_end|>") }))
    }

    private func makeMessage(
        conversationId: UUID,
        role: MessageRole,
        text: String,
        createdAt: Date = Date(timeIntervalSince1970: 0),
        deliveryState: DeliveryState = .delivered,
        sourceProvider: ProviderID
    ) -> ChatMessage {
        ChatMessage(
            conversationId: conversationId,
            role: role,
            text: text,
            createdAt: createdAt,
            deliveryState: deliveryState,
            sourceProvider: sourceProvider
        )
    }
}
