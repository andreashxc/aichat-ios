# Data Persistence

## Technology Stack
- **SwiftData**: Apple's native data persistence framework with Swift-first API
- **ModelContainer**: Shared container created in `BubbleChatApp` and injected via `AppEnvironment`
- **ModelContext**: Owned by `ConversationStore` for transaction management
- **Storage**: On-disk persistence (default); in-memory option available for previews/tests via `ModelConfiguration(isStoredInMemoryOnly: true)`
- **Attachment files**: Image and audio files are stored under `Documents/ChatAttachments` and referenced by path from `ChatMessage`

## Data Models

### Conversation
Properties:
- `id: UUID` - Unique identifier (marked @Attribute(.unique))
- `title: String` - Conversation title (auto-generated or user-edited)
- `createdAt: Date` - Creation timestamp
- `updatedAt: Date` - Last modification timestamp (updated on new messages)
- `providerId: ProviderID` - Active AI provider (`foundationModels` or `local`). Historical cloud IDs remain decodable and are normalized to `foundationModels`.
- `modelName: String?` - Optional specific model name

Relationships:
- One-to-many with `ChatMessage` via conversationId (not explicit relationship, fetched via predicate)

### ChatMessage
Properties:
- `id: UUID` - Unique identifier (marked @Attribute(.unique))
- `conversationId: UUID` - Foreign key to parent conversation
- `role: MessageRole` - Either `.user` or `.assistant`
- `text: String` - Message content
- `createdAt: Date` - Message creation timestamp
- `deliveryState: DeliveryState` - `.pending`, `.delivered`, `.failed`, or `.cancelled`
- `replyToMessageId: UUID?` - Optional reference to message being replied to (for contextual follow-ups)
- `sourceProvider: ProviderID` - Provider that generated this message
- `attachmentPaths: [String]?` - Stored image attachment file paths
- `audioAttachmentPaths: [String]?` - Stored audio attachment file paths

Relationships:
- Many-to-one with `Conversation` (implicit via conversationId)
- Self-referential via replyToMessageId for conversation threading

### LocalModelDescriptor
Legacy SwiftData metadata model retained in the schema. Current local runtime availability is driven by `LocalArtifactStore` manifests under `Application Support/Models/Manifests/`, not by `LocalModelDescriptor`.

Properties:
- `id: UUID` - Unique identifier
- `name: String` - Display name for the model
- `filename: String` - Local file name
- `size: Int64` - File size in bytes
- `hash: String` - Checksum for integrity verification
- `sourceURL: URL` - Original download URL
- `addedAt: Date` - Installation timestamp

Used by: retained persistence compatibility; not the current Model Library source of truth.

## Access Layer: ConversationStore

### Responsibilities
`ConversationStore` is the single source of truth for all data operations. It:
- Encapsulates all SwiftData CRUD operations
- Manages transaction boundaries (save/rollback)
- Enforces business rules
- Provides a clean API to view models

### Core Methods

#### Conversation Operations
```swift
func bootstrapConversation(defaultProvider: ProviderID) -> Conversation
// Fetches most recent conversation or creates new one with welcome message

func createConversation(title: String, providerId: ProviderID) throws -> Conversation
// Creates new conversation with welcome message

func deleteConversation(_ conversation: Conversation) throws
// Deletes conversation, all associated messages, and stored attachment files

func fetchConversation(id: UUID) -> Conversation?
// Fetches specific conversation by ID

func fetchAllConversations() -> [Conversation]
// Fetches all conversations sorted by updatedAt (descending)

func updateConversationTitle(_ conversation: Conversation, title: String)
// Updates conversation title and updatedAt timestamp
```

#### Message Operations
```swift
func fetchMessages(conversationId: UUID) -> [ChatMessage]
// Fetches all messages for a conversation, sorted by createdAt (ascending)

func addMessage(
    text: String,
    role: MessageRole,
    conversationId: UUID,
    deliveryState: DeliveryState = .delivered,
    replyTo: UUID? = nil,
    sourceProvider: ProviderID
) throws -> ChatMessage
// Creates and persists new message, updates parent conversation's updatedAt
```

### Error Handling
- All fetch operations return nil or empty arrays on failure
- Critical insert/delete operations use throwing saves so callers can stop dependent work when persistence fails
- Non-critical updates still use silent saves, but failures are reported to `Logger` and `AppEnvironment.persistenceError`
- `BubbleChatApp` shows a startup error screen if SwiftData cannot create the `ModelContainer` instead of crashing with `fatalError`
- Settings shows the latest persistence error so storage failures can be diagnosed from UI

## Attachment Maintenance

`AttachmentStore` owns attachment file lifecycle:
- `deleteFile(path:)` deletes one stored file and returns reclaimed bytes
- `deleteFiles(paths:)` deletes multiple files and returns total reclaimed bytes
- `deleteAttachments(for:)` deletes image and audio files referenced by messages
- `cleanupOrphanedAttachments(existingMessages:)` removes files in `ChatAttachments` that are no longer referenced by any message

Conversation deletion saves the SwiftData delete first. Attachment files are removed only after the database delete succeeds, avoiding broken references if SwiftData rejects the transaction. Missing attachment files are ignored during deletion.

## Context Budgeting

### ContextBudgeter
Builds bounded prompt history from persisted messages:
- Uses `ContextBudgetProfile` to cap both message count and character count by provider/model.
- Preserves the latest user message when possible.
- Excludes pending, failed, and cancelled messages by default.
- Drops older assistant messages before older user messages when the budget is tight.
- Strips assistant history artifacts such as `<think>...</think>` and local stop tokens.

### Usage Pattern
```swift
let allMessages = conversationStore.fetchMessages(conversationId: id)
let profile = ContextBudgetProfile.defaultProfile(providerId: providerId, modelId: modelId)
let context = contextBudgeter.makeContext(messages: allMessages, profile: profile)
let request = ChatRequest(
    conversationId: id,
    userMessageText: userText,
    contextMessages: context,
    settings: settings
)
```

## Query Patterns

### SwiftUI @Query
Used in `ConversationListView` for reactive updates:
```swift
@Query(sort: \Conversation.updatedAt, order: .reverse)
private var conversations: [Conversation]
```

### ConversationRowView @Query
Fetches messages for last message preview:
```swift
@Query(
    filter: #Predicate<ChatMessage> { $0.conversationId == conversationId },
    sort: [SortDescriptor(\ChatMessage.createdAt, order: .reverse)]
)
private var messages: [ChatMessage]
```

Benefits:
- Automatic UI updates when data changes
- Efficient change tracking
- No manual subscription management

## Transaction Management

### Save Strategy
- `save(operation:)`: Throwing save used for critical operations such as creating messages and deleting conversations
- `saveSilently(operation:)`: Reserved for non-critical metadata updates such as titles, drafts, and streaming text flushes
- Both paths report failures to `Logger`; when `ConversationStore` is owned by `AppEnvironment`, failures also update `AppEnvironment.persistenceError`

### Update Pattern
```swift
func updateConversationTitle(_ conversation: Conversation, title: String) {
    conversation.title = title
    conversation.updatedAt = Date()  // Maintain updatedAt invariant
    saveSilently(operation: "Update conversation title")
}
```

## Future Enhancements

### Planned Features
- **iCloud Sync**: Enable via SwiftData + CloudKit integration
- **Batch Operations**: Bulk delete, archive, export
- **Migration Strategy**: Handle schema changes with versioned migrations
- **Conversation Export**: JSON/Markdown/PDF export functionality
- **Data Cleanup**: Automatic deletion of old conversations
- **Storage Analytics**: Track database size and usage patterns

### Performance Optimizations
- **Pagination**: Load messages in chunks for long conversations
- **Lazy Loading**: Defer loading of message text until visible
- **Background Context**: Use background ModelContext for heavy operations
- **Indexing**: Add indexes on frequently queried fields (conversationId, createdAt)
