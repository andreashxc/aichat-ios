import SwiftData
import XCTest
@testable import AiChat

@MainActor
final class ConversationStoreDeletionTests: XCTestCase {
    private var attachmentDirectory: URL!

    override func setUpWithError() throws {
        attachmentDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiChatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        AttachmentStore.attachmentDirectoryOverride = attachmentDirectory
    }

    override func tearDownWithError() throws {
        AttachmentStore.attachmentDirectoryOverride = nil
        if let attachmentDirectory {
            try? FileManager.default.removeItem(at: attachmentDirectory)
        }
        attachmentDirectory = nil
    }

    func testDeleteConversationDeletesMessages() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Delete me", providerId: .local)

        try store.addMessage(
            text: "Hello",
            role: .user,
            conversationId: conversation.id,
            deliveryState: .delivered,
            sourceProvider: .local
        )

        XCTAssertEqual(store.fetchMessages(conversationId: conversation.id).count, 1)

        try store.deleteConversation(conversation)

        XCTAssertNil(store.fetchConversation(id: conversation.id))
        XCTAssertTrue(store.fetchMessages(conversationId: conversation.id).isEmpty)
    }

    func testDeleteConversationDeletesAttachmentFiles() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Delete attachments", providerId: .local)
        let imagePath = try XCTUnwrap(AttachmentStore.saveImageData(Data([0x01, 0x02, 0x03])))
        let audioPath = try XCTUnwrap(AttachmentStore.saveAudioData(Data([0x04, 0x05]), fileExtension: "m4a"))

        try store.addMessage(
            text: "Attached",
            role: .user,
            conversationId: conversation.id,
            deliveryState: .delivered,
            sourceProvider: .local,
            attachmentPaths: [imagePath],
            audioAttachmentPaths: [audioPath]
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: imagePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioPath))

        try store.deleteConversation(conversation)

        XCTAssertFalse(FileManager.default.fileExists(atPath: imagePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioPath))
    }

    func testMissingAttachmentFileDoesNotCrashDeletion() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Missing attachment", providerId: .local)
        let missingPath = attachmentDirectory.appendingPathComponent("missing.jpg").path

        try store.addMessage(
            text: "Missing attachment",
            role: .user,
            conversationId: conversation.id,
            deliveryState: .delivered,
            sourceProvider: .local,
            attachmentPaths: [missingPath],
            audioAttachmentPaths: [missingPath + ".m4a"]
        )

        XCTAssertNoThrow(try store.deleteConversation(conversation))
        XCTAssertTrue(store.fetchMessages(conversationId: conversation.id).isEmpty)
    }

    func testAddMessageUpdatesConversationDerivedFields() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Derived fields", providerId: .local)
        let createdAt = Date(timeIntervalSince1970: 100)

        try store.addMessage(
            text: "Hello derived fields",
            role: .user,
            conversationId: conversation.id,
            createdAt: createdAt,
            deliveryState: .delivered,
            sourceProvider: .local
        )

        XCTAssertEqual(conversation.messageCount, 1)
        XCTAssertEqual(conversation.lastMessagePreview, "Hello derived fields")
        XCTAssertEqual(conversation.lastMessageDate, createdAt)
        XCTAssertEqual(conversation.lastMessageRole, .user)
    }

    func testUpdateLastMessageTextKeepsPreviewCurrent() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Preview update", providerId: .local)
        let message = try store.addMessage(
            text: "",
            role: .assistant,
            conversationId: conversation.id,
            createdAt: Date(timeIntervalSince1970: 200),
            deliveryState: .pending,
            sourceProvider: .local
        )

        store.updateMessageText(message, text: "Streamed answer")
        store.updateMessageDeliveryState(message, state: .delivered)

        XCTAssertEqual(conversation.messageCount, 1)
        XCTAssertEqual(conversation.lastMessagePreview, "Streamed answer")
        XCTAssertEqual(conversation.lastMessageRole, .assistant)
    }

    func testDeletingLastMessageRestoresPreviousSummary() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Delete last", providerId: .local)
        let first = try store.addMessage(
            text: "First",
            role: .user,
            conversationId: conversation.id,
            createdAt: Date(timeIntervalSince1970: 300),
            deliveryState: .delivered,
            sourceProvider: .local
        )
        let second = try store.addMessage(
            text: "Second",
            role: .assistant,
            conversationId: conversation.id,
            createdAt: Date(timeIntervalSince1970: 400),
            deliveryState: .delivered,
            sourceProvider: .local
        )

        store.deleteMessage(second)

        XCTAssertEqual(conversation.messageCount, 1)
        XCTAssertEqual(conversation.lastMessagePreview, "First")
        XCTAssertEqual(conversation.lastMessageDate, first.createdAt)
        XCTAssertEqual(conversation.lastMessageRole, .user)
    }

    func testDeletingOnlyMessageClearsSummary() throws {
        let store = try makeStore()
        let conversation = try store.createConversation(title: "Delete only", providerId: .local)
        let message = try store.addMessage(
            text: "Only",
            role: .user,
            conversationId: conversation.id,
            createdAt: Date(timeIntervalSince1970: 500),
            deliveryState: .delivered,
            sourceProvider: .local
        )

        store.deleteMessage(message)

        XCTAssertEqual(conversation.messageCount, 0)
        XCTAssertNil(conversation.lastMessagePreview)
        XCTAssertNil(conversation.lastMessageDate)
        XCTAssertNil(conversation.lastMessageRole)
    }

    private func makeStore() throws -> ConversationStore {
        let container = try ModelContainer(
            for: Conversation.self,
            ChatMessage.self,
            LocalModelDescriptor.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ConversationStore(modelContext: container.mainContext)
    }
}
