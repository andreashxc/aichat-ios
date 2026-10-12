# Hybrid Local Models Architecture

This document describes the current local runtime architecture. `LOCAL_MODELS.md` remains the catalog and troubleshooting source of truth.

## Runtime Selection

`LocalProvider` delegates generation to `LocalRuntimeCoordinator`, which:

1. Resolves the selected model definition from `LocalModelRegistry`.
2. Finds verified downloaded variants through `LocalArtifactStore`.
3. Filters variants through `LocalCapabilityService`.
4. Ranks variants using download state, experimental status, backend preference, device type, and size.
5. Renders the prompt with the model-family renderer.
6. Loads the selected artifact through `HybridLocalProvider`.

`HybridLocalProvider` loads the exact variant backend:

- GGUF artifacts use `LlamaEngine` / SwiftLlama.
- MLX artifacts use `MLXEngine` / MLX Swift.

Format and backend are not interchangeable: GGUF requires llama.cpp, and MLX requires MLX.

## Device Gating

- Local inference is disabled in Simulator.
- All local runtimes require iOS 18.0+ on a real iPhone or iPad.
- MLX requires `DeviceCapabilityProfile.supportsMLX`, which currently means real device, iOS 18.0+, and at least 7,500 MB physical memory.
- Stable GGUF variants currently require about 5,500 MB+ physical memory.
- Variants above the recommended model-size budget can still be shown with a warning, but loading may be unstable.

## Supported Current Matrix

| Model definition | Variant | Backend | Artifact | Status |
|---|---|---|---|---|
| `qwen-2.5-3b` | `qwen-2.5-3b-gguf` | SwiftLlama | GGUF single file | Stable |
| `qwen3-1.7b` | `qwen3-1.7b-mlx` | MLX Swift | MLX directory | Stable recommended |
| `gemma-2-2b` | `gemma-2-2b-gguf` | SwiftLlama | GGUF single file | Stable fallback |
| `qwen3-4b` | `qwen3-4b-mlx` | MLX Swift | MLX directory | Experimental |
| `qwen3.5-2b` | `qwen3.5-2b-mlx` | MLX Swift | MLX directory | Experimental |
| `gemma-3-1b` | `gemma-3-1b-mlx` | MLX Swift | MLX directory | Experimental |

## Downloads And Storage

- GGUF downloads use a background `URLSessionDownloadTask`; resume data is stored when iOS provides it.
- MLX downloads query Hugging Face repository metadata, stage required JSON/tokenizer/safetensors files, resume partial files with HTTP range requests, and validate before finalization.
- `LocalArtifactStore` writes one manifest per installed variant. Runtime availability is based on verified manifests, not partial files.
- Startup/refresh repair removes manifests whose artifacts are missing, incomplete, too small, or size mismatched.

## Fallback Behavior

Fallback only happens when a compatible downloaded alternative exists for the same definition. The app does not fall back from Simulator to llama.cpp; Simulator is unsupported for local inference. The app also does not convert MLX to GGUF or GGUF to MLX.

## Known Limits

- Qwen 3, Qwen 3.5, and Gemma 3 are MLX-only in the current catalog.
- Local chat is text-only.
- Additional model families require catalog entries, prompt-renderer validation, download validation, and real-device runtime testing before exposure.
