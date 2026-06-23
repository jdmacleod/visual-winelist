# TODOS

Deferred items from the v2 implementation and design reviews.

## E2: Personal scan history

Save each scan with restaurant name + date. Requires user tagging UI at scan time.

---

## E3: Personal wine cellar

Mark wines tried/want-to-try. Requires user identity model not present in v2.

---

## E5: Purchase links

Vivino + Wine.com deep links per wine detail view.

---

## E6: Card sharing

Share wine card via iOS share sheet / AirDrop.

---



## E9: Scan stats endpoint + curator chart (Phase 4 instrumentation)

`GET /scan/stats` returning per-phase timing aggregates (p50/p95 for `ollama_ms`, `image_ms`, `sommelier_ms`, `total_ms`). Curator header chart showing scan duration trend. Deferred until 50+ scans have accumulated in `scan_log` to establish a meaningful baseline. Foundation (ScanLog timing columns) shipped in v0.2.11.0.

---

## E7: Web design system documentation

Document the web curator's emergent color/typography/component system in DESIGN.md alongside the existing iOS tokens. New contributors currently derive web patterns from reading App.tsx/WineCard.tsx rather than a spec, which risks drift.

---

## E8: Keyboard navigation in ImageCandidatePicker grid

Add arrow-key navigation (←→↑↓) between candidates in the expanded 3x3 picker grid. Tab-only navigation works but is slow for power curators doing batch image curation.

---

## Completed

- **v0.2.4.2** — SSE: iOS UTF-8 chunk boundary fix (`IOSScanSession.swift` → `Data`-based `lineBuffer`)
- **v0.2.4.2** — Security: JPEG magic-byte validation on image upload (`data.startswith(b"\xff\xd8")`)
- **v0.2.4.2** — Backend: `BackendClient.scan()` inner Task cancellation (`continuation.onTermination`)
- **feature/hardening-fixes** — SSE: 1MB lineBuffer cap in both iOS `IOSScanSession` and macOS `BackendClient.scan()` byte loop
- **feature/hardening-fixes** — iOS SSE: `continuation.onTermination` wired in `IOSScanSession.make()` to auto-cancel URLSession on stream break
- **feature/hardening-fixes** — iOS+macOS: URLError mapping added to `checkHealth()` and `fetchImage()` → `BackendError.unreachable`
- **feature/hardening-fixes** — iOS: `BackendClient` session injection (`let session: URLSession = .shared`) for test isolation
- **feature/hardening-fixes** — Tests: `MockURLProtocol` static vars replaced with `actor MockProtocolRegistry`; new `checkHealth`/`fetchImage` iOS tests
- **feature/hardening-fixes** — Swift: `imageTasks: [Task]` replaced with `withThrowingTaskGroup` in both iOS and macOS `WineListViewModel`
- **feature/hardening-fixes** — CI: Swift coverage gate hardened — `llvm-cov` failure now exits non-zero; empty TOTAL is a gate failure
- **feature/hardening-fixes** — Security: `gitleaks/gitleaks-action@v2` full-history scan job added to CI
- **feature/hardening-fixes** — Backend: `--workers 1` enforced in Dockerfile CMD; single-worker constraint documented in `scan.py`
- **feature/hardening-fixes** — Backend: `python:3.13-slim` and `ghcr.io/astral-sh/uv:latest` pinned to SHA256 digests
- **feature/hardening-fixes** — Web: `SortOption` union type updated with `'verified'`; wired to curator sort dropdown; vitest test added
- **feature/test-hardening-2** — iOS: `BackendClient.scan()` now forwards `session.configuration` to `IOSScanSession.make(request:configuration:)`; MockURLProtocol can now intercept scan calls in tests
- **feature/test-hardening-2** — macOS: `MockURLProtocol` static vars + `@unchecked Sendable` replaced with `MacOSMockProtocolRegistry` actor; `loadingTask` tracked and cancelled in `stopLoading()`
- **feature/test-hardening-2** — iOS+macOS: `URLError.cancelled` in `checkHealth()`, `fetchImage()`, and `scan()` now re-throws `CancellationError()` instead of mapping to `BackendError.unreachable`
- **feature/ux-improvements** — P1: `BackendError.invalidImage` added; HTTP 415 in iOS `IOSScanSession` + macOS `BackendClient.scan()` now throws it with actionable message
- **feature/ux-improvements** — P1: macOS `scan()`/`appendScan()` wrap `performScan()` in a stored `Task`; `cancelScan()` cancels via task directly; Cancel button added to scanning view
- **feature/ux-improvements** — P2: `notesIncomplete` session flag removed; `WineDetailView` shows "Tasting notes unavailable" whenever `!isScanning && wine.tastingNote == nil` (covers both dropped-connection and cached-wine cases)
- **Closed (already done in v0.2.4.2)** — URLError mapping incomplete in BackendClient.swift (`.notConnectedToInternet` + `.secureConnectionFailed` were already in the macOS scan() catch)
- **Closed (not worth complexity)** — Performance: Collapse `verified_total` COUNT into main search query (two queries are intentionally different; FILTER clause merge adds complexity for unmeasurable gain at SQLite personal-use scale)
- **feature/image-pipeline-opt (T1)** — WebP variant serving: `GET /wines/{id}/image?size=thumb|card|detail|full`; source-keyed ETag + 304 support
- **feature/image-pipeline-opt (T2)** — Atomic variant writes: `.tmp` + `os.replace()` to prevent partial-file reads
- **feature/image-pipeline-opt (T3)** — Source-keyed ETag from `os.stat(source_path)` shared across all size variants
- **feature/image-pipeline-opt (T4)** — Pre-generation of all variants after upload/set-from-url via `_generate_all_variants()`; thundering-herd eliminated
- **feature/image-pipeline-opt (T5)** — iOS `resizeForUpload` moved to `Task.detached(priority: .userInitiated)`; main actor no longer blocked during photo resize
- **feature/image-pipeline-opt (T6)** — iOS `fetchImage(wineId:size:)` accepts and forwards `?size=` param
- **feature/image-pipeline-opt** — Security: `set_image_from_url` now `follow_redirects=False`; SSRF redirect bypass closed
- **feature/image-pipeline-opt** — Backend: Pillow format normalization (PNG/WebP→JPEG) wrapped in `asyncio.to_thread` in both `wines.py` and `brave_client.py`
- **feature/image-pipeline-opt** — `DELETE /wines/{id}` now cleans up variant files and source JPEG on deletion
- **feature/image-pipeline-opt** — `IMAGE_WEBP_QUALITY` range `[0-100]` validated at startup in `lifespan()`
- **feature/curator-search-query (T1)** — `GET /wines/{id}/image-candidates` accepts `?q=` override; returns `{candidates, query}`
- **feature/curator-search-query (T2)** — ImageCandidatePicker expanded to panel body with 3×3 grid, editable query input, and re-search UX
- **feature/curator-search-query (T3)** — `GET /wines/stats` returns `{total, verified, with_image}`; curator header shows image coverage %
- **feature/curator-search-query (T4)** — Stats fetched on mount and after every image update in `App.tsx`
- **feature/curator-search-query (T5)** — `ScanLog` table added; writes at both CompleteEvent yield sites with try/except guards
- **feature/curator-search-query (T6)** — `GET /scans/recent` returns recent scan summaries + aggregate hit rate; curator header shows hit rate
- **feature/scan-instrumentation-v0.2.11** — iOS `DebugStore`/`DebugHUD`/`WaterfallView` (#if DEBUG); `IOSScanSession` timing hooks; backend `scan_log` timing columns (`ollama_ms`, `image_ms`, `sommelier_ms`, `total_ms`)
