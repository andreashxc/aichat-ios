# Apple On-device (Foundation Models)

- Requirements: iOS 26.0+ and `SystemLanguageModel.default.availability == .available` on the running device. The system can report unavailable because of device, region, language, Apple Intelligence state, or missing OS-managed model assets.
- Provider: `FoundationModelsProvider` (`Providers/FoundationModels/FoundationModelsProvider.swift`) using `SystemLanguageModel.default`.
- Availability: read via `model.availability`; UI surfaces “Model ready” or the unavailable reason. Re-check button re-reads availability.
- Prompt building: `FoundationPromptBuilder` creates a fresh prompt from `ContextBudgeter` output plus optional target message; system instructions enforce concise, non-markdown paragraphs and no emoji unless asked.
- Delivered-only budget rule: Each request creates a new `LanguageModelSession`; no session transcript is reused. Pending, failed, and cancelled messages are excluded, and the Foundation Models profile applies a moderate bounded history budget.
- Download behavior: AiChat does not download Foundation Models. Availability is entirely controlled by iOS.
- Testing notes: use Simulator only for the unavailable path. Real availability and generation must be verified on a real iOS 26+ device where the system model is available.
