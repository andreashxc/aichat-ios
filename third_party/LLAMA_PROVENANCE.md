# llama.cpp runtime provenance

Official source: https://github.com/ggml-org/llama.cpp at b5046, commit 74d4f5b041ad837153b0e90fc864b8290e01d8d5. The runtime is MIT-licensed; the full copyright/permission text is retained in licenses/llama.cpp-b5046-LICENSE.txt and the application ThirdPartyNotices.txt resource.

Official binary: https://github.com/ggml-org/llama.cpp/releases/download/b5046/llama-b5046-xcframework.zip . Its 74,944,281 bytes were downloaded into the private preparation workspace on 2026-10-12 and independently hashed. SHA-256 c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab exactly matches the pinned SwiftLlama 0.4.0 package declaration.

All eight headers in the archive's iOS device slice are byte-identical to the corresponding files at the official source commit. The XCFramework manifest includes iOS arm64 and iOS arm64/x86_64 simulator slices. The iOS binary links only Apple's system frameworks/libraries (Foundation, Metal, Accelerate, CoreFoundation, libSystem, libc++ and libobjc). Its official build-xcframework.sh recipe disables examples, tests, servers and OpenMP; the runtime and embedded Metal code derive from llama.cpp/ggml under MIT. No separate LICENSE/NOTICE file is bundled in the binary archive, so the source license is preserved separately with the app notices.

The binary was not independently rebuilt or executed during preparation. This establishes official-release/checksum/header provenance and license attribution, not an independent security audit or build certification. The binary itself and its debug symbols are excluded from this source export. SwiftPM obtains the checksum-pinned upstream binary when an authorized local build is performed.

SwiftLlama's unused moving master source dependency was removed from the locally vendored exact-version wrapper manifest. The runtime source files and MIT LICENSE remain unmodified; its changes are described in SwiftLlama/RELEASE_MODIFICATIONS.md. Full app build/runtime verification remains blocked by the unaccepted Xcode license on the preparation host.
