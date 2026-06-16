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
