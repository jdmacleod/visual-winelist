# Changelog

## v0.2.12.0 (2026-06-23)

### Added

- **4-across wine grid** — Grid columns increased from 2 to 4, spacing tightened from 12 to 8 pt. ~8 wines visible per scroll on iPhone 15. Card text simplified to wine name only (caption2, one line, truncated) — vintage removed from card overlay; images become primary at this density.
- **Full-bottle detail image** — Fixed 280 pt image panel with blur-background + scaledToFit: the full wine bottle label is visible without scrolling. Wine name, vintage, price, and section appear in a gradient overlay at the bottom of the image. Tasting notes begin immediately below the fold.
- **Preferences screen** — Gear icon in the grid toolbar navigates to a native SwiftUI Form with a "Show price on card" toggle (persisted via `@AppStorage`) and an About section showing the app version.
- **Price overlay badge** — When "Show price on card" is enabled, extracted price appears as a translucent capsule pill at the top-left of each wine card.
- **Consistent version reporting** — All clients (iOS, macOS, backend `/health`, web) now report the version from the single `VERSION` file at the repo root. Backend `/health` response includes a `version` field.

### Fixed

- **Detail image fallback** — A corrupt or partial image response from the backend no longer replaces the working card thumbnail with a placeholder. The detail view now falls back to the grid thumbnail when the high-resolution fetch is undecodable.
- **Detail view thumbnail→detail fade** — The cross-fade transition when the high-resolution image loads was silently broken by the detail view refactor (`.transition(.opacity)` was dead code on an always-present ZStack). Fixed by adding `.id()` to drive SwiftUI identity on image change.
- **Price overlay wrap** — Price text on small cards now truncates to a single line instead of wrapping.

## v0.2.11.0 (2026-06-23)

### Added

- **Scan pipeline timing HUD** (iOS DEBUG builds only) — a draggable, collapsible translucent overlay displays live instrumentation after each scan: screenshot dimensions and size (KB), `http_ok` latency (TCP+TLS+upload+server queue), TTFB, Ollama extraction wall time (`ollama_ms`), image fetch phase (`image_ms`), sommelier phase (`sommelier_ms`), and total scan duration (`total_ms`). A waterfall bar chart shows per-event timing (`wine[n]`, `image[n]`, `complete`).
- **Scan timing columns in ScanLog** — the backend `scan_log` table now records `ollama_ms`, `image_ms`, `sommelier_ms`, and `total_ms` for each completed scan. Existing databases are upgraded automatically on next startup via additive `ALTER TABLE` DDL (idempotent; existing rows retain NULL for the new columns).
- **`image_ms` and `sommelier_ms` in SSE complete event** — all four timing fields now flow from the backend SSE payload through the iOS HUD; the expanded panel shows them individually.

### Infrastructure

- `DebugStore`, `DebugHUD`, `WaterfallView` — new `#if DEBUG`-only Swift types wired to `IOSScanSession` delegate callbacks and `WineListViewModel`. All DebugStore writes from the URLSession delegate queue are dispatched via `Task { @MainActor in }` to respect the `@Observable` main-actor invariant. Stale-task guard via `debugGen` counter prevents cancelled scan metrics from leaking into the next scan's HUD.
- Migration exception handling narrowed to `OperationalError` (was bare `except Exception`) so non-schema errors (DB locked, disk full) surface at startup rather than silently crippling metric persistence.
- `ollama_client`: mid-stream httpx errors (`RemoteProtocolError`, `ReadError`, etc.) now re-raised as `OSError` so they reach the `OLLAMA_DOWN` handler rather than surfacing as opaque `INTERNAL_ERROR` responses.
- `_write_scan_log()` helper extracted — both `INTERNAL_ERROR` and happy-path construction sites now share a single implementation; timing fields are never accidentally omitted on one path.

### Tests

- **Backend**: 184 tests (was 179) — 5 new test functions covering `total_ms` in SSE and ScanLog (happy path + INTERNAL_ERROR + Ollama failure + migration idempotency); existing Ollama-error tests extended with ScanLog persistence and timing assertions.

## v0.2.10.0 (2026-06-23)

### Fixed

- **Shutter button visible on all backgrounds** — The capture button now has a drop shadow so it stays visible when the camera preview is white or bright (e.g. during warm-up or scanning a light-coloured menu).
- **"Scan more" and Trash unblock immediately after extraction** — Both action buttons were disabled until all bottle images finished downloading (30–90s on slow networks). They now re-enable as soon as the backend sends the completion event, while image downloads continue in the background.
- **Vintage and price labels in wine detail** — The vintage year now appears alongside a "vintage" label so it's never confused with a price or section header.

### Infrastructure

- **iOS QA automation** — Integrated DebugBridge + StateServer (DEBUG-only HTTP server) and ObjC touch synthesis (`DebugBridgeTouch`) so the gstack `/ios-qa` skill can drive the app on a real device via USB without Xcode.
- **Session security** — `POST /session/release` now requires a valid session-ID header, preventing one agent from evicting another's active QA session.

### Tests

- Regression test for `isScanning` early-release: verifies the scan buttons unblock at the `.complete` SSE event, not after image downloads finish.

## v0.2.9.0 (2026-06-23)

### Added

- **Gallery density control** — Toolbar button group (4 / 8 / 12 / 16 columns) lets curators switch between a spacious 4-column view and a dense 16-column overview. Selection persists to `localStorage` across reloads. Page size scales with density (density × 5 rows per page), so the total wine count per page stays proportional.

### Fixed

- **Image cache staleness** — `searchWines` and the PATCH response now embed `?v={updated_at_timestamp}` in every image URL. After a label upload, the URL changes, so the browser fetches the fresh image instead of serving the Chrome `max-age=86400` cache entry. `Cache-Control` changed from `public, max-age=86400` to `public, no-cache` to force ETag revalidation on subsequent loads.
- **Escape closes both zoom modal and detail panel** — Pressing Escape while the label-zoom modal was open fired both the zoom handler and the WineDetailPanel handler, closing the detail panel unexpectedly. The zoom Escape handler now calls `e.stopPropagation()` so only the modal closes.
- **Stale density-change fetch** — Changing density while on page > 1 triggered two simultaneous `searchWines` calls (one with the old page, one with page=1). A `fetchId` counter now discards the stale response so only the second, correct call updates the gallery.
- **Space key scrolls page** — `e.preventDefault()` added to the `Space` key handler on WineCard so pressing Space to select a card no longer also scrolls the gallery.
- **"Upload" button label** — The image upload button in WineDetailPanel now reads "Upload" (was "Replace").

### Tests

- **Backend**: 179 tests — new coverage for `?v=` timestamp in `searchWines` and PATCH responses; strengthened assertions to verify the timestamp is a non-zero integer.
- **Frontend**: 94 tests — density control (button rendering, default, localStorage persistence/restore/fallback, pageSize calculation, page reset); WineCard (zoom open/close, Space/Enter/Escape key behaviors); WineDetailPanel ("Upload" label assertion).

## v0.2.8.0 (2026-06-23)

### Added

- **Curator search query** — `GET /wines/{id}/image-candidates` now accepts `?q=` to override the auto-built Brave query. The picker shows the active query in an editable input; submitting triggers a re-search without closing the panel.
- **Image candidate picker expansion** — the picker is now a panel body (flex, fills parent height) instead of an absolute overlay. Shows a 3×3 grid of 9 candidates with aspect-ratio-correct thumbnails.
- **Wine stats endpoint** — `GET /wines/stats` returns `{total, verified, with_image}`. The curator header now displays image coverage (%) updated after every image action.
- **Scan log** — each completed scan writes a `ScanLog` row (scan_id, timestamp, wine_count, cache_hits). Writes at both error-path and happy-path CompleteEvent sites; failures are logged and swallowed so they never block scan delivery.
- **Recent scans endpoint** — `GET /scans/recent?limit=10` returns the N most recent scan summaries and an aggregate `hit_rate` (cache hits ÷ total wines, capped at 100, null when no data).
- **Hit rate in curator header** — the scan hit rate (from `/scans/recent`) is displayed in the header alongside image coverage.

### Fixed

- **Portrait-score rejects negative dimensions** — `_portrait_score` now guards `h <= 0 or w <= 0`, preventing negative-dimension Brave results from sorting above valid candidates.
- **Vintage regex is word-bounded** — `vintageOf()` in `ImageCandidatePicker` now uses `\b...\b` anchors, preventing year extraction from catalog numbers like `SKU-199930`.
- **Candidate grid key stability** — React grid uses `c.url` as key instead of array index; avoids stale-DOM morphing when re-searching returns a different candidate list.

### Tests

- **Backend**: 177 tests — new coverage for `GET /wines/stats` (empty + mixed data), `GET /wines/{id}/image-candidates` with custom `?q=`, `GET /scans/recent` (empty, with data, hit_rate cap, limit param), and `fetch_image_candidates` custom query forwarding.
- **Frontend**: 72 tests — picker tests updated for new `{candidates, query}` return shape; added `populates query input from response` and `search button triggers re-fetch with custom query`.

## v0.2.7.0 (2026-06-22)

### Added

- **WebP variant serving** — `GET /wines/{id}/image?size=thumb|card|detail|full` serves a named WebP variant (thumb=120 px, card=320 px, detail=800 px) or the original JPEG (`full`). Responses include `Cache-Control: public, max-age=86400` and a source-keyed ETag derived from `mtime+size`; matching `If-None-Match` returns 304.
- **Pre-generated variants** — after each upload or image-from-url, all three WebP variants (thumb/card/detail) are generated eagerly via `_generate_all_variants()`, eliminating first-serve latency and thundering-herd on concurrent requests.
- **iOS `fetchImage` size parameter** — `BackendClient.fetchImage(wineId:size:)` now accepts a `size` string and appends `?size=<size>` to the request URL, enabling callers to request appropriately sized images.
- **iOS `resizeForUpload` testability** — the function is now a package-level (not `ContentView`-scoped) function, making it accessible via `@testable import` in unit tests.

### Changed

- **`DELETE /wines/{id}` cleans up image files** — deleting a wine record now also removes all three WebP variant files and the source JPEG, preventing orphaned files from accumulating on disk.
- **iOS `resizeForUpload` runs off main thread** — the 4032×3024 camera photo resize now runs in `Task.detached(priority: .userInitiated)`, keeping the main actor free during CPU-bound JPEG scaling.
- **Atomic variant writes** — `_generate_variant` writes to `{path}.tmp` and uses `os.replace()` for the final rename, ensuring readers never observe a partial WebP file.
- **`set_image_from_url` adds Content-Length pre-check** — the `content-length` header is checked before downloading the body; responses that declare over 2 MB are rejected immediately with HTTP 422.

### Fixed

- **SSRF redirect bypass** — `set_image_from_url` now passes `follow_redirects=False` to httpx. Previously a 301/302 to an RFC-1918 address bypassed the IP validator.
- **Pillow blocking the event loop** — non-JPEG image conversion in `set_image_from_url` and `brave_client._download_image` now runs in `asyncio.to_thread`, preventing Pillow's CPU-bound decode from blocking the asyncio event loop.
- **`_generate_variant` opens source file safely** — `_PILImage.open()` is now wrapped in `try/except Exception` (re-raised as `OSError`), and a zero-width degenerate-image guard prevents ZeroDivisionError during aspect-ratio computation.
- **`IMAGE_WEBP_QUALITY` startup validation** — `lifespan()` raises `ValueError` if the configured value is outside `[0, 100]`, failing fast instead of silently producing corrupt WebP output.
- **`os.path.getsize` race on variant path** — the `getsize` call in `get_wine_image` is now wrapped in `asyncio.to_thread` with an `OSError` guard that returns `-1` if the file disappears between write and stat.

### Tests

- **Backend**: 169 tests — new coverage for variant serving (thumb/card/detail/full), `_generate_variant` unit tests, `_delete_variants` cleanup, upload rollback on missing record, `image-from-url` Content-Length pre-check, and Pillow format normalization path.
- **iOS**: `ImagePipelineTests` — `ResizeForUploadTests` (downscale, passthrough) and `FetchImageSizeTests` (size param appended, default is `card`) using `MockURLProtocol`.

## v0.2.6.0 (2026-06-22)

### Added

- **iOS shimmer animation on loading cards** — wine cards now show a sweeping shimmer highlight while the bottle image is being fetched, matching the macOS loading experience.
- **iOS app icon** — the iOS app now has a custom wine/grapes icon (1024×1024) instead of a generic placeholder.
- **Screen-sleep prevention during scan** — the iPhone display no longer dims or auto-locks while a scan is in progress; the idle timer resets as soon as scanning finishes or the app is backgrounded.

### Changed

- **Fixed-width 2-column iOS grid** — wine cards are sized by dividing the screen width into two equal columns via GeometryReader, eliminating card-width jitter from flexible grid sizing.
- **Bottle-proportioned card aspect ratio** — wine cards use a 3:5 portrait aspect ratio on both iOS and macOS, with `scaledToFit` display so the full bottle height is visible without cropping.

### Fixed

- **"Try again" after a failed append scan returned to the wine grid** — tapping "Try again" from an error clears `errorMessage`, which was triggering a navigation observer to push to the grid (because wines existed) instead of returning to the camera. The observer now only reacts to error-set transitions, not error-clear ones.
- **Zero-width cards on zero-size GeometryReader first pass** — added a `max(1, ...)` floor to the iOS grid's card-width calculation, preventing negative `GridItem(.fixed(...))` sizes on the layout's initial pass.
- **Idle timer stuck enabled on backgrounding mid-scan** — `.onDisappear` on `ContentView` now unconditionally resets `isIdleTimerDisabled = false`, so the screen cannot stay permanently awake if the app exits the view while scanning.
- **Shimmer animation linger after card leaves viewport** — `.onDisappear { phase = -0.4 }` was added to both iOS and macOS `ShimmerOverlay`, resetting the animation target when the card scrolls out of view.
- **Append scan phase guard on error** — if a wine scan returned an error while wines existed, starting a subsequent scan's `performScan` cleared `errorMessage`, which falsely triggered a transition to `.grid` before new wines arrived. Phase now only transitions to `.grid` after a successful scan completion.
- **`URLError.cancelled` type-narrowing** — the NSURLErrorCancelled catch block previously matched any `NSError` with code -999, including errors from unrelated domains. Replaced with a typed `as? URLError, urlErr.code == .cancelled` check.

## v0.2.5.1 (2026-06-22)

### Fixed

- **`scan()` swallowed `CancellationError` on iOS and macOS** — When Swift cancelled a Task awaiting `session.bytes(for:)`, URLSession threw `URLError.cancelled`, which `scan()`'s broad `catch is URLError` mapped to `BackendError.unreachable` rather than re-throwing `CancellationError`. This gap was present despite the same carve-out being correctly applied to `checkHealth()` and `fetchImage()`. Found during pre-landing adversarial review; fix is consistent with the other two methods.
- **iOS `scan()` ignored injected URLSession configuration** — `BackendClient.scan()` called `IOSScanSession.make(request:)` without forwarding `session.configuration`, silently falling back to the default session. `MockURLProtocol` could never intercept scan requests in unit tests because the injected session was unused. Fixed: `session.configuration` is now forwarded to `IOSScanSession.make(request:configuration:)`.

### Tests

- **macOS `MacOSMockProtocolRegistry` actor** replaces static `MockURLProtocol` variables and `@unchecked Sendable`; each test configures state via `async` setters; `tearDown()` is `async throws` and calls `await reset()`. Eliminates a test teardown race where `stopLoading()` could call into an invalidated `URLProtocolClient` on in-flight request cancellation.
- **`MockURLProtocol.loadingTask` cancellation** — `startLoading()` stores the spawned `Task<Void, Never>`; `stopLoading()` cancels it before signalling `onStopLoading`, preventing fire-and-forget callbacks from racing against test teardown.
- **6 new cancellation tests** — 3 macOS (`testCheckHealthCancelledRethrowsCancellationError`, `testFetchImageCancelledRethrowsCancellationError`, `testScanCancelledRethrowsCancellationError`) and 3 iOS (`testIOSCheckHealthCancelledRethrowsCancellationError`, `testIOSFetchImageCancelledRethrowsCancellationError`, `testIOSBackendClientScanForwardsSessionConfiguration`) verify the `URLError.cancelled` → `CancellationError` contract and the session configuration forwarding fix. macOS test suite: 59 → 60 tests.

## v0.2.5.0 (2026-06-22)

### Fixed

- **Unbounded memory growth during SSE** — The line buffer in both iOS and macOS SSE parsers now caps at 1 MB. Malformed oversized pseudo-lines from the server are discarded rather than accumulated.
- **Scanner lock not released on structured cancellation** — When Swift's `withThrowingTaskGroup` unwinds the scan loop (e.g., view dismissed), the URLSession `onTermination` handler now propagates the cancel to `IOSScanSession`, releasing the server's SCANNER_BUSY lock promptly.
- **Image fetch tasks not cancelled on scan abort** — Concurrent image fetches now run inside `withThrowingTaskGroup`. When a scan is cancelled, all in-flight image tasks are cancelled cooperatively. Previously, orphaned image tasks continued running after the scan view was dismissed.
- **`CancellationError` swallowed in image fetch** — The `handleImageEvent` catch block now re-throws `CancellationError` before the generic error handler, allowing `withThrowingTaskGroup` to propagate cooperative cancellation through child tasks correctly.
- **iOS SSE lineBuffer cap was zero** — `sseLineBufferMaxBytes` was defined as a self-reference (`= sseLineBufferMaxBytes`), reducing the 1 MB cap to zero and silently discarding all incoming SSE bytes on iOS.
- **`handleImageEvent` compile error** — The function was declared `async` without `throws`, making `throw CancellationError()` inside it a build-breaking error. Fixed in both iOS and macOS targets.

### Changed

- **`BackendClient` maps `URLError` to `BackendError.unreachable`** in `checkHealth()` and `fetchImage()` (iOS and macOS), so network failures surface a consistent error type to the ViewModel.
- **Docker base images pinned to SHA256 digests** (`python:3.13-slim` and `ghcr.io/astral-sh/uv`) to guard against supply-chain substitution.
- **Backend enforces `--workers 1`** in `Dockerfile CMD`; the rationale (single-Ollama concurrency constraint) is documented inline in `scan.py`.
- **CI coverage gate hardened** — `llvm-cov` failures now exit non-zero; an empty `TOTAL` line is treated as a gate failure rather than a silent pass.
- **CI adds gitleaks full-history scan** — `gitleaks/gitleaks-action` pinned to SHA (v2.3.9) runs on every push to catch secrets committed anywhere in the repo history.
- **Web curator adds "Verified first" sort** — the sort dropdown now surfaces curated wines at the top of the search results.

### Added

- **iOS `BackendClient` exposes injectable `URLSession`** for test isolation, enabling `MockURLProtocol` to intercept network calls in unit tests without a live server.
- **iOS actor-isolated `MockProtocolRegistry`** replaces static `MockURLProtocol` variables, eliminating the `@unchecked Sendable` suppressor and a test teardown race on in-flight request cancellation.

## v0.2.4.2 (2026-06-21)

### Fixed

- **iOS wine names with accented characters** — Wines like "Château" were silently dropped when URLSession split the SSE payload mid-character across delivery chunks. The line buffer now accumulates raw bytes before UTF-8 decoding, so multibyte characters survive any delivery boundary.
- **Scanner lock not released on client disconnect** — Cancelling a scan on iOS or macOS left the server's SCANNER_BUSY lock held for up to 5 minutes because the underlying URLSession connection stayed open after the consumer exited. Cancelling the stream now propagates immediately to the URLSession, releasing the lock promptly.
- **JPEG spoofing via Content-Type header** — The image upload endpoint accepted any file declared as `image/jpeg` without inspecting content. It now verifies the JPEG SOI magic bytes (`\xff\xd8`), rejecting non-JPEG files regardless of Content-Type.
- **Corrupted SSE bytes misinterpreted as event boundary** — An invalid UTF-8 byte in a server response fell back to an empty string, which SSEParser treats as the event-dispatch signal. Wine events could be silently split into two malformed events. The decoder now substitutes U+FFFD for invalid sequences, preserving parser state.

## v0.2.4.1 (2026-06-21)

### Fixed

- **TOCTOU race in scanner lock** — `POST /scan` previously claimed `_scanning = True`
  inside the `_scan_sse` async generator body, which FastAPI only begins iterating after
  returning `StreamingResponse`. Two concurrent requests could both pass the `if _scanning:`
  guard before either set the flag. Lock is now claimed synchronously in the HTTP handler
  before returning `StreamingResponse` with no `await` in between.
- **Orphaned image fetch tasks on client disconnect** — `asyncio.ensure_future()` calls in
  `_scan_sse` were not stored, leaving background Brave fetch tasks running untracked when
  the client dropped the connection. Tasks are now tracked and cancelled in the `finally`
  block alongside `extraction_task`.
- **iOS SSE CRLF line endings** — `IOSScanSession` split on `\n` but did not strip trailing
  `\r`, causing CRLF-terminated lines from HTTP proxies to be fed to `SSEParser` with a
  trailing carriage-return, silently failing to parse event types. macOS `BackendClient`
  already handled CRLF; iOS is now in parity.
- **iOS SSE stream-end without trailing blank line** — `IOSScanSession.didCompleteWithError`
  now flushes any remaining bytes in `lineBuffer` and calls `parser.feed(line: "")` before
  finishing the continuation, dispatching the final pending SSE event when the server closes
  without a trailing `\n\n`. macOS `BackendClient.scan()` already had this flush; iOS is now
  in parity.
- **`NotesSSEPayload.pairings` silences type errors** — both macOS and iOS decoded `pairings`
  with `try? c.decodeIfPresent(...)`, silently returning `[]` on any type mismatch (e.g.
  server sends a string instead of an array). Changed to `try c.decodeIfPresent` so type
  errors propagate to `.parseError` rather than producing silent empty pairings.
- **macOS SSE stream-end flush** — `BackendClient.scan()` calls `parser.feed(line: "")`
  after the byte loop, dispatching any pending SSE event when the server closes without a
  trailing `\n\n`.

### Changed

- **`BackendClient` injectable `URLSession`** — the initializer now accepts an optional
  `session: URLSession` parameter (default `.shared`), enabling unit tests to inject a
  `MockURLProtocol`-backed session without a live server.
- **`.parseError` events logged** — both macOS and iOS `WineListViewModel` now print
  `[SSE] parse error` instead of silently discarding parse failures, making systematic
  backend regressions observable in console output.
- **Coverage thresholds enforced** — vitest now fails if React statement coverage drops below
  80%; pytest fails if Python line coverage drops below 80%. Current baselines: React 87%,
  Python 89%.
- **CI: `web-test` job guard** — the TypeScript test job now skips gracefully when
  `web/package.json` is absent, matching the existing `web-lint` guard pattern.

### Tests

- Python test suite: 110 tests — 8 new tests covering the TOCTOU scanner-lock race, lock
  release on `GeneratorExit`, and image-task cancellation in `_scan_sse`.
- Swift XCTest: 52 tests — added `BackendClient` CRLF, `fetchImage` 200/404, and `URLError`
  mapping tests; iOS `IOSScanSession` cancel-stops-stream and invalid-URL tests;
  `NotesSSEPayload` absent-pairings and `.parseError` passthrough coverage.
- React vitest suite: 48 tests — added `Pagination` component tests (5) and `App` error-path
  tests for `searchWines` rejection and `deleteWine` rejection (2).

## v0.2.5 (2026-06-21)

### Added

- **Curator: status filter** — `GET /wines/search` now accepts `status=all|verified|unverified|no_image`
  to filter the curator grid by curation state.
- **Curator: sort controls** — sort by `name`, `producer`, `created_at`, or `updated_at` with
  `order=asc|desc`. React UI exposes a sort dropdown alongside the status filter.
- **Curator: `verified_total` count** — search responses now include `verified_total: int` so the
  header can show "N verified" without a separate round-trip.
- **Curator: image upload** — `POST /wines/{id}/image` accepts a replacement JPEG (≤ 10 MB) and
  stores it in the image cache. Accessible from the wine detail panel.
- **Curator: inline field editing** — `PATCH /wines/{id}` accepts partial updates for name,
  producer, vintage, variety, and appellation. The detail panel shows an inline edit form.
- **Curator: delete with confirmation** — `DELETE /wines/{id}` removes a record from the cache.
  The React UI shows an animated `ConfirmModal` before executing.
- **`timedFetch`** — all React API calls are now wrapped in a timing shim that logs per-request
  duration to the console, making it easy to spot slow backend calls in devtools.
- **macOS reconnect detection** — `WineListViewModel.notesIncomplete` is set to `true` when the
  SSE stream closes without `event:complete`, surfacing the "connection dropped mid-scan" banner
  in the macOS Wine Detail view.
- **`WineListViewModel` testability** — the view model now takes a `BackendClientProtocol`
  dependency, enabling unit tests with a `MockBackendClient` without a real SSE server.
- **DB indexes** — six single-column indexes added for `name`, `producer`, `appellation`,
  `verified`, `created_at`, and `updated_at` to speed up common filter/sort queries.
- **Image `Cache-Control` header** — `GET /wines/{id}/image` now sets
  `Cache-Control: public, max-age=86400` so browsers/CDNs cache bottle photos for 24 hours.
- **Scan timing metrics** — `event:complete` now includes `ollama_ms`, `image_ms`,
  `sommelier_ms`, and `total_ms` timing fields for performance monitoring.
- **Lazy image loading** — wine card `<img>` tags in the React curator now use `loading="lazy"`
  to defer off-screen image fetches.

### Fixed

- **Path traversal in image upload** — `wine_id` from the URL path is now validated against
  `os.path.realpath` to prevent directory traversal (e.g. `../../etc/...`).
- **Blocking file I/O in async handler** — `open()/write()` in the image upload handler is now
  wrapped in `asyncio.to_thread` to avoid blocking the event loop during large uploads.
- **`update_fields` field allowlist** — `cache.update_fields` now filters incoming dict keys to
  `_EDITABLE_FIELDS`, preventing unconstrained `setattr` from setting non-editable columns.
- **`update_image` race condition** — if a wine record is deleted between the initial lookup
  and the file write, the orphaned file is cleaned up and HTTP 404 is returned (was HTTP 200).
- **`handleVerify` double-count** — `verified_total` delta in `handleVerify` now computes
  against the previous in-state `verified` value rather than using a fixed `+1/-1`, preventing
  double-counting on rapid re-clicks.
- **Stale `actionError` across wines** — action error messages are now cleared when the selected
  wine changes, preventing wine A's error from showing on wine B's detail panel.
- **`WinePatch` blank string validation** — `PATCH /wines/{id}` now rejects blank/whitespace-only
  strings with HTTP 422, preventing empty names from being written through direct API calls.
- **`page=0` negative offset** — `GET /wines/search?page=0` previously computed `OFFSET=-20`,
  which SQLite silently mapped to 0, returning duplicate page-1 results. `page` now enforces
  `ge=1` via `Query`.
- **Scan timing sentinel** — `t_extraction_end` and `t_phase1_end` in `scan.py` now use
  `Optional[float] = None` instead of `0.0`, replacing falsy-checks with explicit `is not None`
  guards.
- **`handleUpdate` `verified_total` tracking** — when a PATCH response returns a different
  `verified` value, `verified_total` is now adjusted accordingly (defensive guard).

### Tests

- Python test suite: 102 tests (was 40), covering image upload, field patch, search filter/sort,
  and cache service edge cases.
- React vitest suite: 34 tests (was 0), covering `WineCard`, `WineDetailPanel`, `ConfirmModal`,
  and all API client functions including `patchWine` and `uploadWineImage`.
- Swift XCTest: macOS `WineListViewModel` reconnect detection (4 test cases).

## v0.2.4 (2026-06-21)

### Fixed

- **iOS: all wines now appear after scanning** — the scan was silently cancelled
  as soon as the first wine arrived. `scanningView.onDisappear` was firing
  `cancelScan()` when SwiftUI transitioned to the grid view on the first wine
  event, killing the SSE connection. The Cancel button already handles
  intentional cancellation; the `onDisappear` hook was removed.
- **Backend: scanner lock released on client disconnect** — if the iOS app
  navigated away mid-scan, `_scanning` stayed `True` permanently and every
  subsequent scan returned HTTP 503 `SCANNER_BUSY` until the server restarted.
  The `_scan_sse` async generator now wraps its full body in `try/finally`,
  which correctly fires on `GeneratorExit` (a `BaseException`) when the client
  drops the SSE connection.

### Changed

- **Ollama image resolution increased to 2048px** — the maximum image dimension
  sent to Ollama was raised from 1024px to 2048px to improve text legibility on
  dense wine lists. With `num_ctx=8192`, a 2048px photo produces ~1100 visual
  tokens — well within budget while preserving fine-print detail that matters
  for accurate wine extraction.

## v0.2.3 (2026-06-20)

### Chore

- **SwiftLint** — added SwiftLint v0.63.3 to pre-commit hooks and CI
  (`swift-ci` job). Config in `.swiftlint.yml`: 120/140 line length,
  `identifier_name` with excluded `[id, ok, ns]`, `cyclomatic_complexity`
  warning=15/error=30. Clean baseline: 0 errors, 13 warnings (test short vars
  and iOS `WineListViewModel` complexity are the known warnings).
- **swift-format enforcement** — pre-commit hook and CI step now enforce
  formatting for all Swift under `Sources/`, `Tests/`, `ios/Sources/`,
  `ios/Tests/`. Uses format+diff pattern (replaces the advisory `lint`
  subcommand that exits 0 on violations). 10 source files reformatted to
  match `.swift-format` config.

## v0.2.2 (2026-06-20)

### Fixed

- **SSE empty-line bug** — `URLSession.AsyncBytes.lines` silently drops empty
  lines, which are the SSE event-boundary signal. `BackendClient.scan()` now
  iterates raw bytes, splitting on `\n` and preserving empty lines exactly as
  `IOSScanSession` does. Previously the macOS client always received 0 wines.
- **Qwen3-VL thinking mode** — `"think": False` is now sent in Ollama options
  (primary) with an assistant pre-fill `{` as belt-and-suspenders for older
  Ollama builds. Without this, Qwen3-VL emits a `<think>` block before JSON
  output, which the token-buffer logic cannot parse.
- **`_scanning` lock covers sommelier phase** — the busy-lock (`_scanning`) was
  previously released before Phase 2 (sommelier notes), allowing a concurrent
  scan to interleave with the single-instance Ollama session. Lock now covers
  the full scan lifecycle.
- **Ollama pre-fill defensive check** — `ollama_client.py` now guards against
  future Ollama builds that might echo the pre-fill `{` in streamed tokens,
  which would produce malformed `{{...}` JSON.
- **Docker startup ordering** — `curator` now depends on `api` with
  `condition: service_healthy` (was `service_started`), so nginx only starts
  routing traffic after the FastAPI server passes its health check.
- **`OLLAMA_BASE_URL` default removed** — `.env.example` no longer sets a
  default `OLLAMA_BASE_URL`, preventing Docker-internal URL bleed-through when
  running outside Docker.

### Added

- **Docker Compose curator profile** — `docker compose --profile curator up`
  starts the React curator frontend at `http://localhost`, proxying API calls
  to the backend container internally.
- **`scripts/test-scan.py`** — diagnostic script to exercise the `/scan` SSE
  endpoint directly and report per-wine extraction results.

## v0.2.1 (2026-06-20)

### Security

- **Secret scanning pre-commit hook** — gitleaks v8.27.2 is now enforced as the
  first pre-commit hook, blocking commits that contain API keys or credentials
  before they reach git history. See `.gitleaks.toml` for allowlisted placeholder
  values.
- **Non-root Docker container** — the backend FastAPI process runs as a pinned
  system user (UID 1001) rather than root, limiting blast radius of a future RCE.
  On Linux hosts, volume directories (`./image-cache`, `./data`) must be
  pre-created with `chown -R 1001:1001` before starting; macOS Docker Desktop
  handles this transparently.
- **`.env` permission guidance** — `CONTRIBUTING.md` now documents `chmod 600 .env`
  and the `OLLAMA_BASE_URL` configuration option for contributors.

## v0.2.0 (2026-06-18)

### Added

- **iOS connection-drop indicator** — if the backend SSE stream closes before delivering
  all tasting notes, wines missing notes now show a `wifi.slash` banner ("Tasting notes
  unavailable — connection dropped mid-scan") in the detail view instead of silently
  showing nothing. Wines that already received notes are unaffected.
- **Canonical WineObject schema** — `shared/wine-schema.json` defines the 10 extraction
  fields as a JSON Schema draft-07 document. Contributors can rely on this as the single
  source of truth when syncing `WineObject.swift`, `WineObject` Pydantic model, and
  `wine.ts`.
- **CI schema drift enforcement** — `backend/tests/test_schema_sync.py` runs on every
  push and fails if the Python Pydantic model drifts from `wine-schema.json`, catching
  field mismatches before they reach clients.

## v0.1.0 (2026-06-16)

Initial proof-of-concept release. macOS app that photographs a printed or
handwritten restaurant wine list and turns it into a visual grid of tappable
bottle images, using a local Ollama model (Qwen3-VL) for text extraction and
Brave Image Search for bottle photos.

- Camera capture with retry on transient macOS Continuity Camera "Reactions"
  video-effect glitches
- Local Ollama (Qwen3-VL) streaming extraction of wines from a photographed
  list
- Brave Image Search bottle photo lookup, with ranked (non hard-filtered)
  candidate selection and per-attempt failure logging
- Wine grid view with a "Clear" button to reset and a "Scan more" flow for
  multi-page lists
- Wine detail sheet with extraction debug info (raw OCR text, confidence,
  parsed fields, Brave query)
