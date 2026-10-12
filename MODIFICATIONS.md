# Release preparation modifications

Clean public source edition by Andrew Manuilov. This directory is a clean source export without Git history.

Removed personal signing-team settings, assigned sample bundle identifiers, removed obsolete documentation/presentation pages and placeholder model data, restored the original icon after the owner confirmed it was theirs, stopped logging prompt/user-message excerpts, and made interpolated application log messages private. Removed four restricted/unverified model downloads, retained only verified Apache-2.0 Qwen 3 variants, and updated tests to use synthetic prompt fixtures for excluded families. Vendored exact MIT-licensed SwiftLlama runtime sources and removed its unused moving llama.cpp dependency; the official b5046 binary target/checksum remain unchanged. Signing must be configured by a distributor.

Added standard Apache-2.0 licensing for original code, attribution, third-party notices and ignore rules for local state.
