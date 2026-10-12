import XCTest
@testable import AiChat

final class FoundationPromptBuilderTests: XCTestCase {
    func testPromptIncludesDeliveredHistoryAndTarget() {
        let context: [ContextMessage] = [
            ContextMessage(id: UUID(), role: .user, text: "Hello", replyToMessageId: nil),
            ContextMessage(id: UUID(), role: .assistant, text: "Hi there", replyToMessageId: nil)
        ]

        let target = "Focus on this part."
        let prompt = FoundationPromptBuilder.buildPrompt(
            context: context,
            userMessage: "Tell me more",
            targetMessage: target
        )

        XCTAssertTrue(prompt.systemInstructions.contains("concise on-device assistant"))
        XCTAssertTrue(prompt.body.contains("Reference message: \(target)"))
        XCTAssertTrue(prompt.body.contains("User: Hello"))
        XCTAssertTrue(prompt.body.contains("Assistant: Hi there"))
        XCTAssertTrue(prompt.body.contains("User: Tell me more"))
    }
}
