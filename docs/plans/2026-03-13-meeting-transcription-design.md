# Meeting Transcription with Speaker Diarization

**Date:** 2026-03-13
**Status:** Approved

## Overview

Add a meeting recording mode to MyWhispers. A separate keyboard shortcut toggles meeting recording on/off. While recording, the menu bar icon shows a pulsing red dot. On stop, the app saves the audio to a WAV file, runs WhisperX (Python CLI) for transcription with speaker diarization, formats the output as Markdown, and presents a save dialog.

## Approach

**Shell out to WhisperX CLI** (Approach A). The app writes recorded audio to a temporary WAV file, then invokes the `whisperx` binary from an auto-installed Python venv. This is the simplest integration path — WhisperX's CLI handles transcription, alignment, and diarization in one call.

## Architecture

```
MeetingHotkey (toggle) → AudioCapture → WAVWriter (stream to disk)
                                              │
                                         Stop recording
                                              │
                                              ▼
                                      WhisperXRunner (Process)
                                              │
                                              ▼
                                      Parse JSON → Format Markdown
                                              │
                                              ▼
                                      NSSavePanel → Save .md file
```

Meeting recording reuses the existing `AudioCapture` (16kHz mono Float32) but streams samples to a WAV file on disk instead of keeping them in memory (meetings can be long).

Only one recording mode at a time — starting a meeting blocks quick-record, and vice versa.

## New Files

### WAVWriter.swift
- Opens file handle on start, writes WAV header with placeholder data size
- Appends PCM Float32 samples as they arrive from AudioCapture's tap
- On stop: seeks back to header, patches the data size, closes file
- Temp file: `~/Library/Application Support/MyWhispers/recordings/meeting-YYYY-MM-DD-HHmmss.wav`

### MeetingRecorder.swift
Orchestrates the full meeting flow:
1. Start AudioCapture + WAVWriter
2. On stop: finalize WAV, invoke WhisperX CLI
3. Parse JSON output into segments with speaker labels
4. Format as Markdown (consecutive same-speaker segments merged)
5. Open NSSavePanel, default filename `Meeting-YYYY-MM-DD-HHmm.md`
6. Clean up temp WAV file

### WhisperXInstaller.swift
Auto-installs WhisperX on first use:
1. Check if `~/Library/Application Support/MyWhispers/whisperx-env/bin/whisperx` exists
2. If not, prompt user: "WhisperX is required. Install now?"
3. Run `python3 -m venv whisperx-env && whisperx-env/bin/pip install whisperx`
4. Show progress in menu bar status

## Modified Files

### AppState.swift
- Add `isMeetingRecording`, `isMeetingProcessing` state
- Add `startMeetingRecording()`, `stopMeetingRecording()` toggle flow
- Conflict guard: block quick-record during meeting and vice versa
- Register `KeyboardShortcuts.onKeyDown(for: .meetingRecord)` toggle handler

### SettingsStore.swift
- Add `hfToken: String` (persisted, for WhisperX diarization)

### SettingsView.swift
- Add "Meeting" section:
  - `KeyboardShortcuts.Recorder("Meeting shortcut:", name: .meetingRecord)`
  - `SecureField` for HuggingFace token with help link

### MenuBarLabel.swift
- Add pulsing red dot state for meeting recording (distinct from steady red dot for quick-record)

### MyWhispersApp.swift
- Add "Start Meeting Recording" / "Stop Meeting Recording (HH:MM:SS)" menu item
- Add "Transcribing meeting..." disabled item + "Cancel Transcription" during processing

### AudioCapture.swift
- Add callback hook so samples can be streamed to WAVWriter alongside the existing buffer

## WhisperX CLI Invocation

```bash
whisperx-env/bin/whisperx meeting.wav \
  --model small \
  --device cpu \
  --compute_type int8 \
  --language <from settings or auto> \
  --diarize \
  --hf_token <from settings> \
  --output_format json \
  --output_dir /tmp/mywhispers-output/
```

Model size reuses the existing setting. WhisperX downloads its own faster-whisper models (separate from whisper.cpp GGML models).

## Output Format

Markdown with speaker labels and timestamps:

```markdown
# Meeting Transcript
**Date:** 2026-03-13 14:30
**Duration:** 45 minutes

---

**SPEAKER_00** (0:00)
Hello, welcome to the meeting. Today we'll discuss the roadmap.

**SPEAKER_01** (0:05)
Thanks for setting this up. I have a few items to cover.
```

## Error Handling

- **Missing HF token:** Alert with link to HuggingFace, explain pyannote terms acceptance
- **Python3 not found:** Alert asking user to install Python
- **WhisperX process fails:** Alert with stderr output
- **No timeout:** User can cancel via menu bar or shortcut

## macOS Constraints

- WhisperX has no Metal/MPS support — CPU only with `int8` compute type
- `float16` compute type fails on macOS — must use `int8`
- HuggingFace token + pyannote model agreement required for diarization
- Audio is microphone only (no system audio capture)

## What's NOT Changing

- Existing quick-record flow (hold-to-record → whisper.cpp → text injection)
- whisper.cpp engine, ModelManager, TextInjector, RecordingIndicator
