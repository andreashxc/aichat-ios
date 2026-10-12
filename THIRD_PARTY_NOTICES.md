# Third-party notices

Apache-2.0 applies to original AiChat code. Dependencies, system frameworks and downloaded models keep their own terms.

## Swift dependencies

Exact revisions are in `third_party/swift-package-inventory.json` and Package.resolved. Full pinned license texts, including vendored notices, are in `third_party/licenses/` and the application resource `Resources/ThirdPartyNotices.txt`.

- GzipSwift, MLX Swift, MLX Swift Examples, NetworkImage, Splash, Swift Markdown UI and SwiftLlama: MIT.
- Swift Collections, Swift Numerics: Apache-2.0 with their upstream Swift runtime exception.
- Swift Jinja and Swift Transformers: Apache-2.0.
- swift-cmark: BSD-style and MIT notices in COPYING.
- MLX vendored fmt, nlohmann JSON and Apple metal-cpp: their full MIT notices are retained.
- SwiftLlama 0.4.0 runtime sources are vendored at exact upstream revision 469310012506c307f3f6800d9c5f31e670ff068d under their MIT license. Only Package.swift was changed to remove the unused moving llama.cpp master dependency and absent test target. The official checksum-pinned llama.cpp b5046 XCFramework remains MIT and is fetched by SwiftPM, not vendored here. Its checksum and all eight iOS headers were independently verified against official sources. See third_party/SwiftLlama/RELEASE_MODIFICATIONS.md and third_party/LLAMA_PROVENANCE.md.
- Apple frameworks and SDKs remain subject to Apple terms.

## Models and owner-confirmed icon

No model weights are bundled. Model download links do not grant permission to use or redistribute their weights. `MODEL_PERMISSIONS.md` records the per-model status. The owner confirmed the original app icon is theirs. It is retained byte-for-byte as an owner-confirmed original asset.
