# Explanation: architecture & data flow

## Overview

Extraction, image search, and caching run in the **FastAPI backend**, not on the phone. The iOS app captures a photo, POSTs it to `/scan`, and renders results as they stream back over Server-Sent Events (SSE). See [backend/README.md](../../backend/README.md) for the API surface and [design decisions](design-decisions.md) for why the work moved off-device.

```
  iPhone (SwiftUI app)                         FastAPI backend
 ┌────────────────────┐                     ┌──────────────────────────────┐
 │ CameraManager      │  JPEG               │ POST /scan                   │
 │  → JPEG Data       │ ──────────────────▶ │                              │
 │                    │                     │  ollama_client → Qwen3-VL    │
 │ IOSScanSession     │   SSE stream        │    (JSONL extraction)        │
 │  (URLSession)      │ ◀────────────────── │  brave_client  → bottle img  │
 │                    │  event: wine        │  cache (SQLite)→ skip lookups│
 │ WineListViewModel  │  event: image       │  sommelier     → notes       │
 │  owns [WineState]  │  event: notes       │                              │
 │                    │  event: complete    │                              │
 └────────┬───────────┘                     └──────────────────────────────┘
          │
          ▼
 ┌────────────────────┐
 │ ContentView        │  AppPhase state machine → WineGridView / WineDetailView
 └────────────────────┘
```

## Camera capture

`CameraManager` (`ios/Sources/VisualWinelistIOS/Camera/CameraManager.swift`) wraps `AVCaptureSession`. It's `@MainActor` for UI-observable state (`isSessionRunning`, `error`) but holds the session and photo output as `nonisolated let` so the preview layer (`CameraPreviewView`) and background configuration work can touch them off the main actor.

`capturePhoto()` takes a single frame, bridging the delegate-based `AVCapturePhotoOutput` API to async/await through a checked continuation. A capture error surfaces as `CameraError.captureError` instead of being swallowed or retried, and diagnostic logging in the `AVCapturePhotoCaptureDelegate` callback makes any future capture failure diagnosable without re-deriving it from scratch.

## The scan request: SSE streaming

`IOSScanSession` POSTs the JPEG to `/scan` and consumes the response with `URLSessionDataDelegate` (rather than `URLSession.bytes(for:)`) so it can hold an explicit `URLSessionDataTask` and cancel the in-flight scan when the user leaves the scanning view. The backend's `routers/scan.py` drives the stream and emits these event types:

- `event: status` — coarse phase signal (e.g. `analyzing`).
- `event: wine` — one extracted `WineObject` (with a server-assigned `wine_id`), emitted as soon as it parses.
- `event: image` — a URL reference to the cached bottle image for a wine (not inline bytes; the client fetches `GET /wines/{id}/image` lazily — see [design decisions](design-decisions.md), D10).
- `event: notes` — a tasting-note-ready signal for a wine, emitted in Phase 2.
- `event: error` — a per-scan failure (e.g. `code: "INTERNAL_ERROR"`).
- `event: complete` — clean end of stream; the client uses this to distinguish a finished scan from a dropped connection.

Extraction (Phase 1) and sommelier notes (Phase 2) cannot run concurrently because Ollama is single-instance, so the backend runs extraction to completion, streaming `wine`/`image` events, then streams `notes` events. The two-phase split is explained in [design decisions](design-decisions.md), D1.

## Extraction: Ollama streaming (backend)

`backend/backend/services/ollama_client.py`'s `extract_wines` POSTs the photo to the configured Ollama server's `/api/chat` endpoint with `stream: true`, then parses the byte stream as it arrives:

1. The request includes an **assistant pre-fill** of `"{"` — without it, Qwen3-VL's "thinking" mode consumes its entire generation budget on internal reasoning and produces zero visible output tokens. The pre-fill skips straight to JSON output. (A structured-output `format` is also sent on Ollama ≥ 0.6.x as belt-and-suspenders.)
2. The prompt (`backend/backend/prompts/wine_extraction.py`) instructs JSONL output (one wine object per line, no markdown, no array wrapper) so wines can be parsed and surfaced incrementally rather than waiting for the entire response.
3. As bytes arrive, a token buffer accumulates and is scanned for complete lines starting with `{`. Each parseable line yields a `WineObject` immediately, which `routers/scan.py` forwards as an `event: wine` — so the grid populates wine-by-wine instead of all at once at the end.
4. If Ollama is unreachable, `extract_wines` raises `ConnectionRefusedError`; a timeout raises `TimeoutError`; a mid-stream network error raises `OSError`. `routers/scan.py` turns these into an `event: error` so the app can show an actionable message.

See [Reference: wine extraction JSON schema](../reference/wine-schema.md) for the full field list and parsing edge cases.

## Image lookup: Brave Search + cache (backend)

For each extracted wine, the backend checks the SQLite cache (`backend/backend/services/cache.py`, keyed by a hash of the wine identity) before calling `backend/backend/services/brave_client.py`'s `fetch_bottle_image`, which:

1. Builds a query from producer (preferred over name — more recognizable) + variety + vintage + `"wine bottle"`.
2. Requests 20 results from Brave Image Search.
3. Ranks results by aspect ratio (closer to a bottle's portrait shape scores higher) rather than hard-filtering non-portrait results out — a result missing dimension data or with a landscape shape is still tried, just later in the order.
4. Downloads the top-ranked candidates in order, stopping at the first success, with a browser-like `User-Agent` header (some retailer CDNs reject hotlinked requests without one).
5. Falls back to a placeholder when every candidate fails; the grid shows a generic bottle icon flagged by region.

Image fetches run concurrently with extraction, so bottle photos start arriving while Ollama is still reading later wines off the same photo. The result is cached, so a repeat scan of the same wine skips the Brave round-trip entirely. See [design decisions](design-decisions.md) for why the original count=5 + hard-filter approach was replaced.

## Sommelier notes (backend, Phase 2)

After the extraction stream closes, `backend/backend/services/sommelier.py` generates a tasting note per wine via Ollama and the backend emits an `event: notes` as each completes. Clients that don't need notes can stop reading after `event: complete` in Phase 1.

## UI phase flow (iOS)

`ContentView` is a single state machine over `AppPhase` (`home`, `camera`, `scanning`, `grid`, `cameraDenied`, `error`) rather than a navigation stack, since the app is one continuous capture-and-browse loop. The app opens on `home`; starting a scan moves to `camera`, capture moves to `scanning`, and the first streamed wine flips to `grid`. `WineListViewModel` publishes `wines`/`errorMessage` from the SSE events, and `ContentView`'s `onChange` handlers translate those into phase transitions.

`WineGridView` renders the live grid plus a "Clear" (reset, return home) and "Scan more" (return to camera, append results — duplicates skipped by name + vintage) toolbar. Tapping a bottle opens `WineDetailView` as a sheet showing the full-bottle image, name, vintage, price, section, and the streamed tasting note; low-confidence reads carry a "?" badge.
