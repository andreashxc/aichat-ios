# Markdown Rendering & Voice Input

## Overview

AiChat now supports rich text rendering with Markdown and voice input via speech-to-text, making it easier to compose messages and view formatted responses.

## Markdown Rendering

### Supported Features

All AI responses and user messages are automatically rendered with full Markdown support:

#### Text Formatting
- **Bold text**: `**bold**` or `__bold__`
- *Italic text*: `*italic*` or `_italic_`
- `Inline code`: `` `code` ``

#### Headings
```markdown
# Heading 1
## Heading 2
### Heading 3
```

#### Lists
**Bulleted Lists**:
```markdown
- Item 1
- Item 2
  - Nested item
```

**Numbered Lists**:
```markdown
1. First item
2. Second item
3. Third item
```

#### Code Blocks
````markdown
```swift
func greet() {
    print("Hello, World!")
}
```
````

Code blocks feature:
- Syntax highlighting for multiple languages (Swift, Python, JavaScript, etc.)
- Horizontal scrolling for long lines
- Glassmorphic background with app glass-material styling
- Monospaced font for readability

#### Blockquotes
```markdown
> This is a blockquote.
> It can span multiple lines.
```

#### Links
```markdown
[Link text](https://example.com)
```

### Styling

Markdown is styled to match the app's glassmorphism design:

**User Messages** (Blue Gradient):
- White text on blue gradient background
- Code blocks with white semi-transparent background
- Gradient borders for enhanced depth

**Assistant Messages** (Glass):
- Primary color text on glass material
- Code blocks with dark semi-transparent background
- Subtle borders for visual separation

### Text Selection

All Markdown content supports text selection:
- Long-press on any message to select text
- Copy specific portions of responses
- Works with all Markdown elements (code, headings, lists, etc.)

## Voice Input (Speech-to-Text)

### How to Use

1. **Tap the Microphone Button**: Located inside the message composer, next to the text field
2. **Grant Permissions**: On first use, you'll be asked to allow:
   - Microphone access
   - Speech recognition
3. **Start Speaking**: The button turns red with a gradient border to indicate recording
4. **See Transcription**: Your speech appears in real-time in the text field
5. **Tap Again to Stop**: Recording stops and the transcription is finalized
6. **Send Message**: Tap the send button as usual

### Visual Indicators

- **Microphone Icon**:
  - Blue gradient when idle
  - Red gradient when recording
- **Recording Border**: Red gradient border around composer field during recording
- **Disabled Input**: Text field is disabled during recording to prevent conflicts

### Features

- **Real-time Transcription**: See your words appear as you speak
- **Automatic Insertion**: Transcribed text automatically fills the composer
- **Error Handling**: Clear error messages if permissions are denied or recognition fails
- **Language Support**: Uses your device's default language for recognition

### Privacy & Security

- **On-Device Processing**: Speech recognition happens on your device (iOS system framework)
- **Permission Required**: Explicit user authorization for microphone and speech recognition
- **No Cloud Upload**: Your voice data stays on your device
- **Clear Descriptions**: Info.plist clearly states why permissions are needed

### Troubleshooting

**"Speech recognition not authorized"**:
- Go to Settings → Privacy & Security → Microphone
- Enable microphone access for AiChat
- Go to Settings → Privacy & Security → Speech Recognition
- Enable speech recognition for AiChat

**"Recognizer unavailable"**:
- Check that your device supports speech recognition
- Ensure your locale/language is supported
- Restart the app and try again

**Recording doesn't stop**:
- Tap the microphone button again
- The recording will auto-stop after 60 seconds (system limit)

## Technical Details

### Markdown Implementation

- **Library**: [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) v2.4.0+
- **Syntax Highlighting**: [Splash](https://github.com/JohnSundell/Splash) v0.16.0+
- **Custom Theme**: `MarkdownTheme+AiChat.swift` with glass-material styling
- **Rendering**: SwiftUI-native, no WebView required

### Speech Recognition Implementation

- **Framework**: Apple Speech (SFSpeechRecognizer)
- **Audio**: AVAudioEngine for microphone input
- **Service**: `SpeechRecognizer.swift` with @Observable pattern
- **Threading**: @MainActor for UI thread safety
- **Logging**: os.Logger for debugging

### Performance

- **Markdown**: Efficient SwiftUI-native rendering, no performance impact
- **Speech**: Minimal battery/CPU usage, on-device processing
- **Memory**: Audio buffers automatically released after recording

## Future Enhancements

Planned improvements for rich text and voice:

### Markdown
- [ ] LaTeX math rendering
- [ ] Table support
- [ ] Mermaid diagram rendering
- [ ] Custom emoji rendering

### Voice
- [ ] Text-to-speech for AI responses
- [ ] Multi-language selection
- [ ] Voice command shortcuts
- [ ] Audio message playback

## Developer Notes

### Adding Custom Markdown Styles

To customize the Markdown theme, edit `AiChat/Utils/MarkdownTheme+AiChat.swift`:

```swift
extension Theme {
    static func aiChat(isUserMessage: Bool) -> Theme {
        Theme()
            .text {
                ForegroundColor(isUserMessage ? .white : .primary)
                FontSize(16)
            }
            // Add more customizations...
    }
}
```

### Extending Speech Recognition

To add custom speech recognition features, modify `AiChat/Domain/Services/SpeechRecognizer.swift`:

```swift
@MainActor
@Observable
final class SpeechRecognizer {
    // Add custom properties or methods
}
```

### Privacy Keys

Required Info.plist keys (already configured):
```xml
<key>NSMicrophoneUsageDescription</key>
<string>AiChat needs microphone access for voice input</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>AiChat needs speech recognition to convert your voice to text</string>
```
