# LLM Transcript Refinement Design

**Date:** 2026-03-14
**Status:** Approved

## Goal

Add optional LLM-based refinement of meeting transcripts to identify speakers by name, fix misattributed sentences at speaker boundaries, and clean up transcription errors.

## Settings

New "Transcript Refinement" section in the Meeting column (column 4):

- **Toggle**: "Refine transcript with AI" (off by default)
- **Provider picker**: OpenAI / Anthropic
- **API Key**: SecureField stored in Keychain
- **Model name**: TextField with per-provider defaults (`gpt-4o` for OpenAI, `claude-sonnet-4-20250514` for Anthropic)
- **Prompt**: TextEditor with customizable default prompt

All fields visible only when toggle is on.

## Refinement Flow

After the native diarization pipeline produces the Markdown transcript:

1. Check if refinement is enabled in settings
2. If yes, send transcript to configured LLM with user's prompt
3. Replace transcript content with LLM response
4. Save to file + notify (existing behavior)

If the LLM call fails, save the raw transcript anyway and show an error notification.

Status messages: "Preparing models..." → "Transcribing & identifying speakers..." → "Refining transcript..."

## LLM API Integration

- `LLMProvider` enum: `.openAI`, `.anthropic`
- `TranscriptRefiner` actor with: `refine(transcript:prompt:provider:apiKey:model:) async throws -> String`

Internally:
- **OpenAI**: POST `https://api.openai.com/v1/chat/completions` with `Authorization: Bearer <key>`
- **Anthropic**: POST `https://api.anthropic.com/v1/messages` with `x-api-key: <key>`, `anthropic-version: 2023-06-01`

No streaming — wait for full response.

## Default Prompt

```
You are a meeting transcript editor. You receive a raw transcript with speaker labels (SPEAKER_00, SPEAKER_01, etc.) and timestamps.

Your tasks:
1. Try to identify speakers by name or role from context clues in the conversation. Replace generic labels with names when confident.
2. Check if parts of sentences at speaker boundaries were attributed to the wrong speaker. Fix any misattributions.
3. Clean up obvious transcription errors while preserving the original meaning.

Return the full corrected transcript in the same Markdown format. Do not add commentary or explanations — only return the transcript.
```

## Scope

### In scope

- Toggle for transcript refinement (off by default)
- LLM provider picker (OpenAI / Anthropic)
- API key stored in Keychain
- Model name with per-provider defaults
- Customizable prompt with sensible default
- Direct HTTP calls to provider APIs
- Status message during refinement
- Fallback: save raw transcript if LLM fails
- `TranscriptRefiner` actor

### Not in scope

- Streaming responses
- Token counting / cost estimation
- Conversation history / multi-turn refinement
- Additional providers (Gemini, Ollama)
- Separate raw + refined file output
