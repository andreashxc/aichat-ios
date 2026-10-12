# User Guide

## Getting Started

### First Launch
When you first open AiChat, you'll see the **conversation list** with all your chats. The app starts with no conversations, showing a helpful empty state with instructions.

### Creating Your First Conversation
1. Tap the **"New Chat"** button (blue gradient compose icon) in the top-right corner
2. A new conversation appears in the list
3. Tap the conversation to open it
4. Type your first message in the text field at the bottom
5. Tap the send button (blue gradient arrow) to send

### Navigating Between Conversations
- **From conversation list**: Tap any conversation to open it
- **Back to list**: Tap the **"All Chats"** button (chevron + bubbles icon) in the top-left
- **Quick navigation**: Single tap returns you to the conversation list instantly

## Managing Conversations

### Viewing All Conversations
- The conversation list shows all your chats
- Each row displays:
  - Conversation title
  - Last message preview
  - Time since last message (e.g., "5 minutes ago")
- Sorted by most recent activity first

### Creating New Conversations
- Tap the **compose button** (blue gradient) in the conversation list toolbar
- A new conversation is created with the title "New Chat"
- Tap to open it and start chatting
- The title automatically updates when you send your first message

### Deleting Conversations
- **Swipe left** on any conversation in the list
- Tap the **"Delete"** button
- The conversation and all its messages are permanently removed

### Renaming Conversations
1. Open the conversation you want to rename
2. Tap the **menu button** (blue gradient three dots) in the top-right corner
3. Select **"Rename"**
4. Enter a new title in the text field
5. Tap **"Save"** (blue gradient button)

### Searching Conversations
- Use the **search bar** at the top of the conversation list
- Type to filter conversations by title
- Results update in real-time as you type
- Tap the X to clear the search

### Opening a Conversation
- Tap any conversation in the list to open it
- The chat view opens with your full message history
- Use the "All Chats" button (top-left) to return to the list

## Chatting

### Sending Messages
1. Type your message in the text field at the bottom
2. Press **Return/Enter** to add a new line (not send)
3. Tap the **send button** when ready
4. Your message appears immediately in blue on the right

### Receiving Responses
- Assistant responses appear in gray on the left
- Messages are delivered paragraph-by-paragraph
- A typing indicator (animated dots) shows when the assistant is thinking
- Each paragraph appears with a slight delay for a natural feel

### Stopping Generation
- During response generation, the send button becomes a **"Stop"** button
- Tap it to interrupt the response
- Already-delivered paragraphs remain visible
- Undelivered paragraphs are discarded

### Copying Messages
1. **Long-press** any message bubble (user or assistant)
2. Select **"Copy"** from the menu
3. The message text is copied to your clipboard

## Advanced Interactions

### Asking for Clarification
When an assistant message is unclear:
1. **Long-press** the assistant message bubble
2. Select **"Clarify"**
3. A composer sheet opens with a pre-filled template
4. Edit the question if needed
5. Tap **"Send"** to ask for clarification

Example template: "Can you clarify: \"[first part of message]...\""

### Requesting More Details
To learn more about an assistant's response:
1. **Long-press** the assistant message bubble
2. Select **"Tell me more"**
3. A composer sheet opens with "Tell me more about this"
4. Edit the request if desired
5. Tap **"Send"** to get more details

### Understanding Reply Tracking
- When you use "Clarify" or "Tell me more", your message includes a reference to the original message
- The provider receives a bounded delivered-message context plus the target message reference when available.

## Settings

### Accessing Settings
- From conversation list: Tap the **gear icon** in the toolbar
- From chat view: Tap the **menu button** → **"Settings"**

### Storage Maintenance
- Use **Clean orphaned attachments** to remove stored image or audio files that are no longer referenced by any conversation.
- Settings reports how much disk space was reclaimed after cleanup.
- If the app detects a persistence failure, Settings shows the latest storage error for troubleshooting.

### Changing Providers
Currently supported providers:
- **Foundation Models** (Apple on-device) - Available on iOS 26+ only when the system reports `SystemLanguageModel.default` as available
- **Local Models** - Available on iOS 18+ real iPhone/iPad devices when device memory meets the selected variant's requirements

OpenAI, Claude/Anthropic, and other cloud providers are not supported in the current app. Old conversations that reference retired cloud provider IDs are migrated to Foundation Models.

### Managing Local Models
- Open Settings -> Manage Models to see the curated Qwen and Gemma variants.
- Stable variants are shown by default. Enable "Show Experimental Models" in Model Settings to reveal experimental Qwen/Gemma builds.
- Downloaded models become selectable only after files are validated on disk.
- Delete an installed variant from Manage Models to reclaim storage.

## Tips & Tricks

### Automatic Titles
- The first message you send becomes the conversation title
- Only the first 6 words are used (plus "..." if longer)
- You can always rename it manually later

### Multi-line Messages
- Press **Return/Enter** to add line breaks
- The text field supports up to 4 lines
- After 4 lines, it scrolls internally

### Keyboard Shortcuts (iPad)
- **⌘N**: New conversation (planned)
- **⌘W**: Close conversation (planned)
- **⌘F**: Search conversations (planned)

### Empty States
If you see an empty state:
- **"No Conversations"**: Tap compose to start your first chat
- **"Select a conversation"**: Choose one from the list
- **"Model unavailable"**: Check Settings to configure your AI provider

## Troubleshooting

### Foundation Models Not Available
If you see "Foundation Models unavailable":
1. Ensure you're running iOS 26+.
2. Enable **Apple Intelligence** in Settings -> Apple Intelligence & Siri when that setting exists on the device.
3. Check that the device, region, and language support Apple's on-device Foundation Models.
4. Tap **"Re-check"** in Settings -> Provider Settings and read the system unavailable reason.

### Local Models Not Available
If no local models appear:
1. Use a real iPhone or iPad. Local inference is disabled in Simulator.
2. Use iOS 18.0 or newer.
3. Open Settings -> Manage Models.
4. Download a compatible model variant for your device.
5. Return to Model Settings and select the downloaded model.

### Local Model Download Problems
- **Model not downloaded**: Start or resume the download in Settings -> Manage Models. Partial downloads are not selectable until validation succeeds.
- **Model too large**: Choose a smaller GGUF model on lower-memory devices, or use an MLX-capable device with 7,500 MB+ physical memory.
- **MLX unavailable**: Use a real iOS 18+ device with 7,500 MB+ memory. If unavailable, choose a GGUF variant where one exists.
- **Simulator unsupported**: Run on a physical iPhone or iPad for local downloads and generation.
- **iOS version unsupported**: Update to iOS 18+ for local models or iOS 26+ for Foundation Models.

### Messages Not Sending
If your message doesn't send:
- Check that the text field isn't empty
- Ensure you're not already generating a response (Stop button visible)
- Try restarting the app

### Conversations Not Appearing
If conversations disappear:
- Check your search bar isn't filtering results
- Verify you haven't accidentally deleted them

## Data & Privacy

### Local Storage
- All conversations are stored locally on your device
- Data is saved using SwiftData (Apple's persistence framework)
- Supported generation providers run on-device; no provider prompts are sent to cloud inference APIs.

### iCloud Sync
- Currently not available
- Planned for future release
- When available, conversations will sync across all your devices

### Deleting Data
- Swipe to delete individual conversations
- To delete all data: Delete and reinstall the app
- Bulk delete coming in future update

## What's Next?

Upcoming features (see IMPROVEMENTS.md for details):
- **Local Models**: Expand supported downloadable model variants
- **Image Support**: Send and receive images
- **Voice Input**: Speak your messages
- **Export**: Save conversation history
- **Folders**: Organize conversations into categories
- **iCloud Sync**: Access chats on all devices

## Feedback & Support

Found a bug or have a suggestion?
- Read the documentation in the Docs/ folder

---

*Last updated: 2026-05-17*
