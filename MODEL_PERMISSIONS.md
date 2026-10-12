# Model permissions

Checked 2026-10-12 against the listed download repositories. This source release does not include model weights. The offered download catalog contains only Qwen3 1.7B and Qwen3 4B MLX variants. Apache-2.0 on AiChat code does not relicense models.

| Catalog download | Observed upstream terms | Release implication |
| --- | --- | --- |
| bartowski/Qwen2.5-3B-Instruct-GGUF | Qwen Research License, base Qwen/Qwen2.5-3B-Instruct | Excluded from release catalog. Noncommercial research/evaluation only; commercial permission requires a separate license. |
| mlx-community/Qwen3-1.7B-4bit | Apache-2.0 model card | Retain actual model license/notices when redistributing weights. |
| mlx-community/Qwen3-4B-4bit | Apache-2.0 model card | Retain actual model license/notices when redistributing weights. |
| mlx-community/Qwen3.5-2B-4bit-OptiQ | Repository metadata unavailable (HTTP 401) | Excluded from release catalog: unavailable and unverified. |
| bartowski/gemma-2-2b-it-GGUF | Gemma terms | Excluded from release catalog. Reintroduction requires review and compliance with Google Gemma terms; not Apache-2.0. |
| mlx-community/gemma-3-1b-it-4bit | Gemma terms | Excluded from release catalog. Reintroduction requires review and compliance with Google Gemma terms; not Apache-2.0. |

The active catalog in LocalModelCatalog.swift offers only the two verified Apache-2.0 Qwen 3 repositories. Four restricted/unverified downloads were removed. Generic legacy prompt-format support is retained for compatibility; this does not grant rights to any weights and does not provide a download for excluded models. No new user-import feature was added. A distributor who later includes weights must retain the actual model license, notices and relevant modifications. Users who separately obtain other models remain responsible for their terms; the app license supplies no blanket grant. Downloads currently point at mutable upstream repositories, so reproducible binary/model distribution requires artifact revision and integrity verification. Full base-model Apache licenses are included in third_party/model-licenses.


Sources: https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/blob/main/LICENSE ; each named repository model card; https://ai.google.dev/gemma/terms . No terms were accepted on anyone's behalf and no weights were downloaded during preparation.
