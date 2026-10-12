# Chat UX Behavior

## Visual Design

### Message Layout
- **iMessage-inspired layout**: Assistant messages on the left (gray background), user messages on the right (black background)
- **Bubble styling**: Rounded corners (20pt radius), padding, max-width constraint (320pt), with iMessage-style tails
- **Message tails**: Small curved tails on bottom-left (assistant) or bottom-right (user) of bubbles for authentic iMessage feel
- **Spacing**: 12pt vertical spacing between messages, horizontal padding from edges
- **Typing indicator**: Animated dots bubble appears during assistant response generation
- **Composer placement**: Fixed at bottom with gradient fades above and below
- **Content visibility**: Full message visibility with 120pt bottom padding for composer clearance
- **Gradient overlays**: Smooth gradient fades at top and bottom of composer area for seamless blending
- **Scroll behavior**: Smart auto-scroll - scrolls to bottom when sending message or when user is already at bottom
- **New messages indicator**: Black pill button with arrow and unread count appears when scrolled up and new messages arrive

### Conversation List
- **Stack navigation**: NavigationStack with NavigationLink for seamless conversation selection
- **Conversation rows**: Display title, last message preview, and relative timestamp
- **Search functionality**:
  - Toggle search with magnifying glass icon in toolbar
  - Auto-focuses search field when opened
  - Searches both conversation titles and message content
  - Real-time filtering as you type
  - Clear button to reset search
- **New chat composer**:
  - Fixed at bottom with gradient fades above and below
  - Identical design to in-chat composer for consistency
  - Multi-line text input with microphone button for voice input
  - Glass morphism style with gradient borders
  - Send button activates when text is entered
- **Empty states**: Helpful messages when no conversations exist
- **Last message preview**: Shows sender prefix ("You:" for user messages) and truncated text
- **Monochrome icons**: All navigation icons use primary color for consistency
- **App launch**: Starts with conversation list instead of auto-selecting first chat

## Interaction Patterns

### Message Delivery
- **Delivery model**: Chat generation creates one assistant placeholder and updates it in place until the response is delivered, failed, or cancelled
- **Incremental display**: Local runtimes stream partial text into the assistant bubble; Foundation Models currently return a complete response
- **Smart auto-scroll**:
  - When user sends message: Always scrolls to bottom to show typing indicator
  - When new messages arrive: Scrolls only if user was already at bottom
  - When user scrolls up: Shows "new messages" button instead of forcing scroll
- **Unread tracking**: Tracks last read message count; shows count of unread messages in pill button
- **Manual scroll**: User can tap pill button to jump to bottom and mark all as read
- **Cancellation**: Stop button interrupts generation, preserves partial text as cancelled when present, and removes the typing indicator

### Context Menu Actions
- **Long-press activation**: Hold on any message bubble to reveal context menu
- **Assistant message actions**:
  - **"Clarify"**: Instantly sends message asking for clarification with quote (first 100 chars)
  - **"Tell me more"**: Instantly sends message requesting elaboration
- **All message actions**:
  - **"Copy"**: Copy message text to clipboard
- **Instant sending**: Context actions send messages immediately without modal dialogs
- **Context preservation**: Reply actions include replyToMessageId linking to original message
- **Auto-scroll**: After sending clarify/tell me more, chat auto-scrolls to bottom to show response

### Conversation Management
- **Create**: Type message in bottom composer of conversation list and tap send
  - Creates new conversation with user's message
  - Automatically navigates to the new chat
  - Auto-generates response based on selected provider
  - Title auto-generated from first message (first 6 words + "..." if longer)
- **Delete**: Swipe left on conversation row to reveal delete button
- **Rename**:
  - Auto-generated title from first message (first 6 words + "..." if longer)
  - Manual rename via pencil button in chat toolbar → modal sheet
- **Search**: Tap search icon in toolbar to toggle search field, filter by title
- **Navigate**: Tap conversation row to navigate to chat view
- **Return**: Single tap custom back button (chevron + bubbles icon) to return to list

### Input & Sending
- **Composer**: Glass-style text field with multi-line support (up to 4 lines)
- **Send button**: Disabled when text is empty; shows paper plane icon
- **Stop button**: Replaces send button during generation; shows "Stop" text
- **Keyboard submission**: Return key adds new line (not send)
- **Title generation**: First message in conversation auto-generates title

## State Feedback

### Loading States
- **Typing indicator**: Animated dots bubble during response generation
- **Stop button**: Visual indication that generation is in progress
- **Disabled composer**: Text field remains enabled during generation for queuing

### Empty States
- **No conversations**:
  - Icon: bubble.left.and.bubble.right
  - Message: "No Conversations"
  - Hint: "Tap the compose button to start a new chat"
- **No selection**:
  - Icon: message
  - Message: "Select a conversation"
  - Hint: "Choose a chat from the list or create a new one"

### Error States
- **Provider unavailable**: Error message bubble explaining issue (e.g., "Foundation Models unavailable: [reason]")
- **Missing local model**: Error message explains that a compatible local model must be downloaded or selected

## Accessibility
- **Dynamic Type**: Text scales with system font size settings
- **Color contrast**: Adequate contrast ratios for message bubbles
- **VoiceOver**: All interactive elements are labeled (planned improvements)
- **Reduced motion**: Respect system animation preferences (planned)

## Current Status
- ✅ Unified assistant placeholder updates for Foundation Models and local providers
- ✅ Context menu actions ("Clarify", "Tell me more", "Copy") with instant sending
- ✅ Message reference tracking for context-aware replies
- ✅ Conversation CRUD operations (create, read, update, delete)
- ✅ Advanced search: searches both titles and message content with auto-focus
- ✅ Auto-generated and manual conversation titles
- ✅ Markdown rendering with custom glass-material theme
- ✅ Speech-to-text voice input with microphone button
- ✅ Message deduplication to prevent duplicate display
- ✅ Clean composer layout with smooth gradient fades
- ✅ Monochrome design (black/white/gray only)
- ✅ iMessage-style bubble tails for authentic messaging feel
- ✅ Smart auto-scroll behavior based on user position
- ✅ Unread messages indicator with count badge
- ⏳ Context budgeting enhancement to use replyToMessageId metadata for targeted retrieval (planned)
- ⏳ Message editing/regeneration (planned)
