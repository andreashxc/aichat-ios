# Local models in the release candidate

The active download catalog is LocalModelCatalog.swift. It offers only mlx-community/Qwen3-1.7B-4bit and the experimental mlx-community/Qwen3-4B-4bit, both verified against Apache-2.0 model cards and official Qwen base-model licenses. No weights are included in the source archive.

Qwen 2.5 3B (research license), Gemma 2/3 (separate Gemma terms), and the unavailable Qwen 3.5 OptiQ entry are excluded. Runtime prompt-format support for historical models remains for compatibility; it is not a grant of rights to weights. See the project-root MODEL_PERMISSIONS.md for exact obligations and source links.

The llama.cpp backend uses the source-pinned local SwiftLlama wrapper and the official checksum-pinned b5046 XCFramework. See third_party/LLAMA_PROVENANCE.md from the project root. No model terms were accepted during preparation.
