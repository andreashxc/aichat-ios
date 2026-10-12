# Testing Strategy

## Developer Verification Checklist

Build:
```sh
xcodebuild -project AiChat.xcodeproj -scheme AiChat -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

Unit tests:
```sh
xcodebuild -project AiChat.xcodeproj -scheme AiChat -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

Manual matrix:
- iOS Simulator, iOS 18+: UI launches, persistence works, Foundation Models unavailable path is visible, local inference is disabled.
- Real iOS 18+ iPhone/iPad around 5,500 MB+ memory: download and run a stable GGUF variant such as Qwen 2.5 3B or Gemma 2 2B.
- Real iOS 18+ iPhone/iPad with 7,500 MB+ memory: download and run Qwen 3 1.7B MLX; verify token streaming and Model Settings runtime status.
- Real iOS 26+ device: verify Foundation Models Settings availability and generate when `SystemLanguageModel.default` is available.
- Migration: open a persisted conversation/settings payload with legacy `openAI` or `anthropic` and confirm it resolves to Foundation Models.

Device diagnostics:
- Open Settings -> Device Diagnostics.
- Capture device identifier, iOS version, Simulator flag, RAM, MLX support, recommended backend, GPU cache, max recommended model size, and warnings.
- Include diagnostics with any local model or Foundation Models availability issue.

## Coverage

- Unit tests:
  - `ContextBudgeterTests` covers context truncation, latest-user preservation, assistant-first pruning, failed/cancelled filtering, and Qwen history sanitation.
  - `FoundationPromptBuilderTests` validates prompt construction includes delivered history and reference message text.
- Manual/targeted:
  - Foundation Models availability must be exercised on a real iOS 26+ device because Simulator reports unavailable.
  - Local model generation must be exercised on real devices because Simulator disables local inference.
  - Cancellation: verify Stop removes typing indicator and drops undelivered paragraphs.
  - Paragraph splitting: actor keeps contiguous bullet lists together for text-processing coverage.
- UI smoke tests: send-and-display flow for ChatView should cover Foundation Models availability failures and local streaming updates.
