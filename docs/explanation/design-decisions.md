# Explanation: design decisions

## Why local Ollama instead of a cloud vision API

Wine list photos are photos of someone else's menu — often from a restaurant the user doesn't own. Running extraction through a local Qwen3-VL model means the photo and its text never leave the user's Mac, which avoids both a privacy concern and a class of "are we allowed to send this to a third party" questions that a cloud OCR/vision API would raise. The tradeoff is dependency on the user having Ollama installed and a capable-enough model pulled, and slower inference than a hosted API would offer (10–60s per photo).

## Why an assistant pre-fill of `"{"` for Qwen3-VL

Qwen3-VL has a "thinking" mode that, left alone, spends its entire generation budget on internal chain-of-thought reasoning and emits no visible response tokens — the request would complete with empty output. Pre-filling the assistant turn with `"{"` skips the model past thinking mode directly into JSON generation. This is a model-specific workaround, not a general prompting technique; if the model is swapped out, this should be the first thing re-validated (`Scripts/eval-extraction.swift` exists for exactly this).

## Why JSONL instead of a single JSON array

Streaming the extraction response lets each wine populate the grid as soon as it's parsed, rather than holding everything until the full response (and full inference run) completes. A JSON array would require the entire array to close before any single object could be safely parsed out of it. JSONL means each line is independently parseable as soon as it ends.

## Why ranked Brave candidates instead of a hard portrait filter

The original implementation requested 5 results and hard-filtered to images with an aspect ratio (height/width) above 1.2 — anything below that ratio, or missing dimension data entirely, was dropped. In practice this could zero out every candidate even when Brave's own UI clearly had usable bottle photos available: a 5-result pool is small, and any single result missing `properties.width`/`height` from the API silently vanished rather than being deprioritized.

The fix (see `Sources/VisualWinelist/Brave/BraveSearchClient.swift`) was to:
- Raise the requested result count from 5 to 20, so there's a larger pool to rank from
- Replace the hard filter with a continuous ranking score (closer to portrait scores higher, but nothing is excluded) so a landscape or dimension-less result is still tried — just later
- Add a `User-Agent` header, since some retailer CDNs return 403 on hotlinked requests with no UA, which had been silently swallowed into a generic "no usable image" before
- Try up to 8 ranked candidates (download attempts) instead of giving up after 3
- Log per-result dimensions/ratio/portrait verdict and per-download failure reason, so a future "no image found" report can actually be diagnosed instead of investigated from scratch

`Scripts/validate-brave-hitrate.swift` predates these fixes and still exercises the old count=5 + hard-filter logic standalone — useful for measuring raw per-tier Brave coverage, but not a live mirror of the production client's current ranking behavior.

## Why camera capture retries instead of fixing the root cause

Captured frames are occasionally corrupted by macOS Continuity Camera's "Reactions" video-effects renderer (visible as `VFXNode` errors in the console) — a system-level issue outside this app's control. Rather than disabling Continuity Camera features (which the user may want for other apps) or surfacing a capture error to the user on the first glitch, `CameraManager.capturePhoto` retries up to 3 times with a short delay, since the underlying issue is transient and the next frame is reliably clean.

## Why a single `AppPhase` state machine instead of separate views/navigation

The app is fundamentally one continuous loop — point camera, capture, wait, browse results, maybe capture again — not a set of independently navigable screens. Modeling it as one `ContentView` switching over an `AppPhase` enum keeps the camera session, view model, and transition logic in one place and avoids the overhead of a navigation stack for a flow that never needs back-stack semantics beyond "return to camera."

---

## v2 architecture decisions

### Why a self-hosted backend instead of keeping Ollama on-device

The v1 constraint that required Ollama running locally on a Mac was a hard blocker for two things: iOS support (inference at 15–30 s on-device made the UX unusable) and shared image caching across devices. Moving extraction and image search to a backend removes both blockers simultaneously: a single Ollama instance serves all clients, the image cache is shared, and an iPhone can scan a wine list at a restaurant table without running a 6 GB model locally.

### Why "sent to your server" is different from "sent to a third-party cloud"

The original v1 privacy statement — "wine list text never leaves your Mac" — was specifically about third-party cloud OCR/vision APIs (e.g. Google Cloud Vision, AWS Rekognition). The concern was an unknown third party ingesting photos of restaurant wine lists you do not own. A self-hosted backend is a different category: you control the server, you control the data, and the photo goes to a machine you own on your own network. The v2 privacy statement is: *your wine list photo is sent to your self-hosted backend server — not a third-party cloud service*.

This distinction matters for the README and for users deciding whether to deploy v2. The answer to "should I be worried?" is: no more than you would be about any other data you send to a server you run yourself.

### Why two-phase SSE for sommelier notes (D1)

The extraction phase (Phase 1) and the sommelier phase (Phase 2) cannot run concurrently because Ollama is single-instance. If both phases tried to call Ollama simultaneously, one would queue and effectively run serially anyway — but the client would have no visibility into which wines were still waiting for notes and which had finished.

Two-phase SSE makes this explicit: Phase 1 emits `event: wine` and `event: image` events as extraction completes; Phase 2 emits `event: notes` events after the extraction stream closes. Clients that don't need notes can disconnect after `event: complete` in Phase 1. The total SSE connection duration for a 30-wine list is 2–3 minutes; `event: complete` signals a clean end vs. a network drop.

### Why SQLite instead of PostgreSQL (D2)

The backend runs on a personal server where Docker Desktop's overhead already consumes resources. Adding a Postgres container for a single-user deployment would double the memory footprint for no practical benefit. SQLite with SQLAlchemy's async driver (aiosqlite) is sufficient for the write volume (a few scans per day) and the read volume (curator search queries). The SQLAlchemy ORM makes a future PostgreSQL migration straightforward if community hosting ever requires it.

### Why `event: image` carries a URL reference, not inline base64 (D10)

At 30 wines × ~150 KB per image, inlining base64 image data in the SSE stream would produce an 81 MB SSE payload. The `/wines/{wine_id}/image` endpoint already exists for serving cached image bytes. Clients fetch images lazily via that endpoint after receiving the URL reference in `event: image`, keeping the SSE stream lightweight regardless of image count.

### Why the iOS SSE client uses URLSessionDataDelegate instead of async/await bytes (D5)

The iOS client needs to cancel the in-flight URLSession task when the user navigates away from the scanning view (T10). `URLSession.bytes(for:)` — the async/await streaming API used by the macOS client — does not expose the underlying `URLSessionDataTask` directly, so there is no clean way to cancel it from a different call site. `URLSessionDataDelegate` stores the task at construction time (`IOSScanSession.dataTask`) and exposes a `cancel()` method. The macOS client uses `bytes(for:)` because it does not need task cancellation at the view level.
