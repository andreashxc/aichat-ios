# SwiftLlama release preparation

Upstream: https://github.com/ShenghaiWang/SwiftLlama at 469310012506c307f3f6800d9c5f31e670ff068d (0.4.0), MIT. LICENSE and all selected runtime Swift sources are unmodified.

Package.swift changes: removed the unused llama.cpp master source dependency; removed the test-target declaration because upstream test sources are not included in this runtime-only vendor copy. The binary target remains the official b5046 URL and SHA-256 c19be78b5f00d8d29a25da41042cb7afa094cbf6280a225abe614b03b20029ab. The 74,944,281-byte official archive was independently downloaded for private verification and matched this checksum. No framework bytes are included in this source export.
