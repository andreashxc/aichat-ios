# Model Download Lifecycle

AiChat treats local model installs as staged artifacts until `LocalArtifactStore` writes a verified manifest. Runtime code only sees manifests that still match files on disk, so interrupted or incomplete downloads never appear installed.

## Preflight

Before a download starts, `ModelDownloadManager` resolves the expected byte count:

- GGUF: `HEAD` first, then a ranged `GET` fallback for Hugging Face resolve URLs. If the server cannot report size, the catalog variant size is used.
- MLX: Hugging Face repository metadata is fetched and required file sizes are summed. If metadata is incomplete, the catalog variant size is used.

The manager compares required bytes with available volume capacity and surfaces a clear insufficient-storage error with both required and available bytes.

## GGUF Downloads

GGUF variants use a background `URLSession` download task. The task description stores the variant id so callbacks can be associated with the model after session handoff.

Cancellation and transport interruption save `resumeData` under `Application Support/Models/Staging/<variant>.resumeData` when iOS provides it. Starting the same variant again resumes from that data; if resume data is unavailable or invalid, the download restarts cleanly.

On completion, the temporary file is size-checked and moved into place by `LocalArtifactStore.finalizeGGUFDownload`. The manifest is written only after the move succeeds.

## MLX Downloads

MLX variants stage files under `Application Support/Models/Staging/<variant>/` and persist state in `<variant>.staging.json`.

The state records each required repository file, expected size, current bytes, completion, attempts, and last error. Existing partial files are reused with HTTP `Range` requests. If the server ignores a range request, the affected file is restarted instead of trusting mismatched bytes.

Each file is retried with exponential backoff. Progress is byte-based across all required files, and the UI shows both downloaded bytes and total bytes.

Before finalization, every required file is validated for presence, nonzero size, and exact metadata size when known. `LocalArtifactStore.finalizeMLXDownload` then atomically moves the staging directory into the model directory and writes the manifest.

## Repair

At startup and refresh, `LocalArtifactStore.repairManifests()` removes manifests whose artifacts are missing, too small, size-mismatched, or incomplete. This keeps model selection based on verified artifacts only.
