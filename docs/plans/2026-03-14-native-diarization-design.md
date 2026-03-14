# Native Speaker Diarization with TitaNet via sherpa-onnx

**Date:** 2026-03-14
**Status:** Approved

## Goal

Add a built-in speaker diarization option that requires no HuggingFace token, using sherpa-onnx with TitaNet embeddings. The existing WhisperX/pyannote path remains available as an alternative.

## User-Facing Settings

New **diarization engine** picker in Meeting settings:

- **"Built-in (TitaNet)"** — default, no token needed, models downloaded on first use
- **"WhisperX (pyannote)"** — current behavior, requires HF token

When "Built-in" is selected, the HF token field is hidden. When "WhisperX" is selected, the token field appears as today.

New `DiarizationEngine` enum stored in `SettingsStore`.

## Architecture

### Library Integration

Add sherpa-onnx as a C library dependency (vendored or SPM), similar to how whisper.cpp is vendored today. sherpa-onnx provides a C API callable from Swift.

### Models (~95 MB total, downloaded on first use)

| Model | Size | License | Purpose |
|-------|------|---------|---------|
| TitaNet-Large ONNX | ~90 MB | CC-BY-4.0 | Speaker embeddings |
| Silero VAD v6 ONNX | ~2 MB | MIT | Voice activity detection / segmentation |

Spectral clustering is built into sherpa-onnx (no extra model).

Models stored in `~/Library/Application Support/MyWhispers/models/` alongside existing whisper GGML models. Downloaded from sherpa-onnx GitHub releases.

### Diarization Pipeline (Built-in path)

1. Silero VAD segments audio into speech regions
2. TitaNet extracts speaker embeddings per segment
3. Spectral clustering groups embeddings into speakers (up to 8)
4. Speaker labels mapped onto whisper.cpp transcript segments by timestamp alignment

Key: the built-in path uses **whisper.cpp for transcription + sherpa-onnx for diarization** (two native engines). The WhisperX path continues to do both in one Python call.

## Transcription Flow

### Built-in (TitaNet) path

1. Record audio to WAV (unchanged)
2. Transcribe with whisper.cpp → segments with timestamps
3. Run sherpa-onnx diarization on same WAV → speaker labels with timestamps
4. **Merge step** (new Swift code): align whisper segments with diarization output by overlapping time ranges, assign speaker label to each segment
5. Format as Markdown (same output format as today)

### WhisperX (pyannote) path

Unchanged from current implementation.

### Merge Logic

For each whisper.cpp segment `[start, end]`, find the diarization speaker label with the greatest time overlap. If no overlap (silence/gap), label as "UNKNOWN".

### Output Format

Identical regardless of engine — same Markdown with `**SPEAKER_00**` labels and timestamps.

## Model Management

- Download on first use (not bundled in app binary)
- Reuse existing `ModelManager` download + progress patterns
- Download triggered when user first starts a meeting transcription with "Built-in" engine selected
- Source: sherpa-onnx GitHub releases (can mirror to S3 later)

## Error Handling

- **First-use download fails**: Show error, allow retry
- **Poor diarization results**: If overlap is ambiguous, fall back to "UNKNOWN" speaker label
- **Single speaker detected**: Labels as `SPEAKER_00` — consistent format
- **Engine switch mid-recording**: Not allowed — takes effect on next transcription
- **WhisperX not installed but pyannote engine selected**: Existing behavior — prompts to install

## Scope

### In scope

- `DiarizationEngine` enum and setting
- sherpa-onnx C library integration
- TitaNet + Silero VAD model download
- Native diarization pipeline (VAD → embeddings → clustering)
- Timestamp-based merge of whisper.cpp transcription + diarization
- Settings UI update (engine picker, conditional HF token field)

### Not in scope

- Speaker name assignment (mapping SPEAKER_00 to "Alice")
- Real-time diarization during recording
- Custom number-of-speakers setting
- S3 model hosting
- Bundling models in app binary
