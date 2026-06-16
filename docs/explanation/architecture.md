# Explanation: architecture & data flow

## Overview

```
                 ┌─────────────────┐
   tap to scan → │  CameraManager   │ → JPEG Data
                 └─────────────────┘
                          │
                          ▼
                 ┌─────────────────┐
                 │  OllamaClient    │ streams WineObject per JSON line
                 │ (Qwen3-VL local) │
                 └─────────────────┘
                          │
                          ▼
                 ┌──────────────────────┐
                 │ WineListViewModel     │ owns [WineState], drives UI phase
                 └──────────────────────┘
                          │  (per wine, concurrently)
                          ▼
                 ┌─────────────────┐      ┌──────────────┐
                 │ BraveSearchClient│ ───▶ │  ImageCache   │
                 │  (image lookup)  │ ◀──  │ (~/.visual-   │
                 └─────────────────┘      │  winelist/)   │
                          │
                          ▼
                 ┌─────────────────┐
                 │ WineGridView /   │
                 │ WineDetailView   │
                 └─────────────────┘
```

## Camera capture

`CameraManager` (`Sources/VisualWinelist/Camera/CameraManager.swift`) wraps `AVCaptureSession`. It's `@MainActor` for UI-observable state (`isSessionRunning`, `error`) but holds the session and photo output as `nonisolated let` so the preview layer (`CameraPreviewView`) and background configuration work can touch them off the main actor.

`capturePhoto()` retries up to 3 times with a 250ms gap. This isn't defensive programming for a hypothetical failure — macOS Continuity Camera's "Reactions" video-effects renderer intermittently corrupts a single captured frame (visible as `VFXNode... patching invalid duplicated core entity handle` in the console), and the next frame is reliably clean. Diagnostic logging in the `AVCapturePhotoCaptureDelegate` callback exists to make any future recurrence diagnosable without re-deriving this from scratch.

## Extraction: Ollama streaming

`OllamaClient.extractWines` POSTs the photo to a local Ollama server's `/api/chat` endpoint with `stream: true`, then parses the byte stream as it arrives:

1. The request includes an **assistant pre-fill** of `"{"` — without it, Qwen3-VL's "thinking" mode consumes its entire generation budget on internal reasoning and produces zero visible output tokens. The pre-fill skips straight to JSON output.
2. The prompt instructs JSONL output (one wine object per line, no markdown, no array wrapper) so wines can be parsed and surfaced incrementally rather than waiting for the entire response.
3. As bytes arrive, a token buffer accumulates and is scanned for complete lines starting with `{`. Each parseable line yields a `WineObject` immediately, so the grid populates wine-by-wine instead of all at once at the end.
4. If the connection is refused (Ollama not running), the stream surfaces `OllamaError.connectionRefused` with a message telling the user to run `ollama serve`. If parsing yields zero wines, it surfaces `OllamaError.noWinesFound`.

See [Reference: wine extraction JSON schema](wine-schema.md) for the full field list and parsing edge cases.

## Image lookup: Brave Search

For each extracted wine, `WineListViewModel.fetchImage` first checks `ImageCache` (keyed by SHA256 of lowercased name + vintage), then falls back to `BraveSearchClient.fetchBottleImage`, which:

1. Builds a query from producer (preferred over name — more recognizable) + variety + vintage + `"wine bottle"`.
2. Requests 20 results from Brave Image Search.
3. Ranks results by aspect ratio (closer to a bottle's portrait shape scores higher) rather than hard-filtering non-portrait results out — a result missing dimension data or with a landscape shape is still tried, just later in the order.
4. Downloads the top 8 ranked candidates in order, stopping at the first successful download, with a browser-like `User-Agent` header (some retailer CDNs reject hotlinked requests without one).
5. Returns `nil` if every candidate fails, in which case the grid shows a generic placeholder bottle icon colored/flagged by region.

Every wine's image fetch runs in its own `Task`, kicked off as soon as the wine is extracted rather than after the full extraction stream completes — so bottle photos start arriving while Ollama is still reading later wines off the same photo.

See [Explanation: design decisions](design-decisions.md) for why the original count=5 + hard-filter approach was replaced.

## UI phase flow

`ContentView` is a single state machine (`AppPhase`: `.camera` / `.scanning` / `.grid` / `.error`) rather than separate screens/navigation stack, since the whole app is one continuous capture-and-browse loop. `WineListViewModel` publishes `wines`/`errorMessage`, and `ContentView`'s `onChange` handlers translate those into phase transitions (e.g. first non-empty `wines` flips `.camera` → `.grid`).

`WineGridView` renders the live grid plus a "Clear" (reset to empty, return to camera) and "Scan more" (return to camera, append results) toolbar. Tapping a bottle opens `WineDetailView` as a sheet, which includes an `EXTRACTION DEBUG` panel — the raw OCR text, confidence, parsed fields, and the exact Brave query used — useful during development for diagnosing why a particular wine extracted or matched poorly.
