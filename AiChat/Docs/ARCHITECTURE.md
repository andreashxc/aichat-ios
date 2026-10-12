# Architecture

## Layers
- **App**: `BubbleChatApp` creates the shared SwiftData container and injects `AppEnvironment`. If container creation fails, startup falls back to a diagnostic error screen instead of terminating the process.
- **Domain**: SwiftData models (`Conversation`, `ChatMessage`, `LocalModelDescriptor`) and provider/domain types (`ProviderID`, `ChatRequest`, `ModelInfo`, `GenerationSettings`).
- **Services**: `ConversationStore` encapsulates full CRUD operations for conversations and messages; `AttachmentStore` owns stored image/audio file lifecycle; `ContextBudgeter` builds provider/model-aware prompt history with message and character budgets.
- **Features**:
  - `ConversationListView`: Master-detail navigation with conversation list and chat detail
  - `ChatView` + `ChatViewModel`: Chat UI with typing indicator, stop control, and paragraph delivery
  - `MessageBubbleView`: Individual message bubbles with context menus
  - `ReplyComposerSheet`: Contextual follow-up composer
  - `EditConversationTitleSheet`: Rename conversations
  - Settings screens surface provider options and availability
- **Providers**: Foundation Models and local runtimes are the only supported generation providers. Legacy cloud provider IDs remain decodable and normalize to Foundation Models during migration.
- **Utils**: logger, capability checks, attachment storage, and shared errors.

## Data flow

### Conversation Management
```
User -> ConversationListView -> @Query(conversations)
User taps "New Chat" -> ConversationStore.createConversation() -> SwiftData insert
User selects conversation -> ChatViewModel(conversationId) -> ChatView
User swipes to delete -> ConversationStore.deleteConversation() -> SwiftData delete -> AttachmentStore.deleteFiles()
User searches -> Filter applied to @Query results
```

### Message Flow
```
User -> ChatView -> ChatViewModel.sendMessage()
ChatViewModel -> ConversationStore.addMessage(user) -> SwiftData
ChatViewModel -> supported provider generation pipeline -> response text or streaming partials
ChatViewModel -> ConversationStore.updateMessageText(assistant placeholder) -> SwiftData
SwiftData updates -> @Published messages -> ChatView re-renders
ChatView.onChange -> scrollToBottom
```

### Context Menu Interactions
```
User long-press bubble -> Context menu appears
User taps "Clarify" -> handleClarify() -> showReplySheet = true
ReplyComposerSheet -> User edits text -> User taps "Send"
ChatViewModel.sendReply(text, replyingTo: message) -> adds message with replyToMessageId
Provider generates response -> assistant placeholder updates in place
```

### Title Management
```
First message sent -> generateTitle() -> updateConversationTitle()
User taps menu -> "Rename" -> EditConversationTitleSheet
User saves -> ChatViewModel.updateTitle() -> ConversationStore.updateConversationTitle()
SwiftData updates -> UI refreshes
```

## SwiftData schema
- `Conversation`: id, title, createdAt, updatedAt, providerId, modelName
- `ChatMessage`: id, conversationId, role, text, createdAt, deliveryState, replyToMessageId, sourceProvider
- `LocalModelDescriptor`: id, display name, filename, size, hashes, source URL, addedAt

## Dependency injection
`AppEnvironment` owns the shared `ModelContainer`, `ConversationStore`, `ContextBudgeter`, and `FoundationModelsProvider`. Views receive it via `EnvironmentObject`, and view models get a concrete reference during initialization to keep UI logic isolated from storage details. Persistence failures reported by `ConversationStore` are exposed as `AppEnvironment.persistenceError` for alerts and Settings diagnostics.

## Context Policy
- `ChatViewModel` passes the active provider and selected model id into `ContextBudgetProfile.defaultProfile(providerId:modelId:)` before every generation request.
- Foundation Models use a moderate history budget. Local 1B/2B models use a small budget, while local 3B/4B models use a medium budget.
- Context includes delivered messages only by default. Pending, failed, and cancelled messages are excluded unless a profile explicitly opts into failed history.
- The most recent user message is preserved when possible. When the budget is tight, older assistant messages are removed before older user messages.
- Assistant history is sanitized before prompt rendering: hidden `<think>...</think>` blocks and known stop tokens are stripped so local prompts do not replay model artifacts.

## Navigation and UI

### Navigation Structure
- Root: `ConversationListView` with `NavigationSplitView`
  - Sidebar: List of conversations with search bar, last message preview, timestamps
  - Detail: `ChatView` for selected conversation
- Empty states:
  - No conversations: "Tap compose to start"
  - No selection: "Select a conversation"

### Chat UI
- Toolbar: Menu with "Rename" and "Settings" options
- Message bubbles: Assistant (left, gray), User (right, blue)
- Context menus: Long-press for "Clarify", "Tell me more", "Copy"
- Composer: glass-style text field + send or stop button (when generating)
- Typing indicator: Appears during paragraph delivery

### Conversation List UI
- Search bar: Filter by conversation title
- Conversation rows: Title, last message preview, relative timestamp
- Swipe actions: Delete conversation
- Toolbar: "New Chat" button, Settings navigation

## State Management
- `@Query` for reactive SwiftData queries in ConversationListView
- `@Published` properties in ChatViewModel for UI updates
- `@State` for local UI state (sheets, selected conversation)
- `@EnvironmentObject` for shared AppEnvironment

## Planned evolution
- Continue hardening Model Library downloads, runtime diagnostics, and artifact repair
- Enhanced context budgeting to use reply-to metadata for targeted responses
- Conversation folders/categories
- iCloud sync via SwiftData + CloudKit
