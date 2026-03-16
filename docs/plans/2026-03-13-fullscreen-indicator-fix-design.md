# Fix: Recording indicator not visible in full-screen mode

**Date**: 2026-03-13

## Problem

The recording indicator (`NSPanel`) is invisible when the frontmost app is in full-screen mode (particularly cross-platform apps like VS Code, Chrome, Slack). The recording and transcription still work — only the visual indicator is missing.

## Root causes

Two separate issues:

1. **Window level too low**: `.floating` (level 3) sits below full-screen windows. Fixed by raising to `.screenSaver` (level 1000).

2. **VS Code returns (0,0) caret position**: The Accessibility API returns `CGRect.zero` for the caret bounds in VS Code full-screen, causing the panel to be placed off-screen at `y=-32`. Fixed by falling back to the mouse cursor position when caret coordinates are `(0,0)`.

## Changes

`RecordingIndicator.swift`:
- `panel.level` changed from `.floating` to `.screenSaver`
- Added mouse cursor fallback when `caretScreenPosition()` returns nil or `(0,0)`

`Log.swift`:
- Added `Log.ui` logger category
