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



## E10: Upload size reduction experiment

After collecting 10+ scan baselines with the new ScanSettings tuning capability (v0.2.13.0+),
benchmark `uploadMaxSide=1280` + `uploadJPEGQuality=0.75` vs current defaults (1920px / 0.85).
Check HUD `receive_ms` for upload speed improvement and `ollamaMs` for accuracy regression.
If accuracy is unchanged (Ollama reads wine labels equally well at 1280px), reduce the defaults
to cut upload size ~50-70%.

**Depends on:** TTFI instrumentation PR (T1+T2+T5 from perf-ttfi plan). Blocked on baseline data.

---

## E11: Inline base64 images in SSE stream for cached wines

Instead of returning an `ImageEvent` URL and requiring a separate `GET /wines/{id}/image`
round-trip per cached wine, embed the card-size WebP bytes as a base64 field directly in the
SSE `image` event. iOS decodes and displays without a second HTTP call. For a scan with 5
cached wines, eliminates 5 round-trips.

Requires: SSE protocol change (new optional `data_b64` field in ImageEvent), iOS decode,
size limit guard (~50KB per wine card at 320px WebP, safe), and a backend size check to avoid
streaming multi-MB originals. Measure current per-image round-trip time with URLSessionTaskMetrics
before committing — if round-trips are <100ms on LAN, skip this.

**Depends on:** URLSessionTaskTransactionMetrics implementation (T2 from perf-ttfi plan).

---

## E9: Scan stats endpoint + curator chart (Phase 4 instrumentation)

`GET /scan/stats` returning per-phase timing aggregates (p50/p95 for `ollama_ms`, `image_ms`, `sommelier_ms`, `total_ms`). Curator header chart showing scan duration trend. Deferred until 50+ scans have accumulated in `scan_log` to establish a meaningful baseline. Foundation (ScanLog timing columns) shipped in v0.2.11.0.

---

## E12: Telemetry endpoint hardening (P3)

`POST /telemetry/scan` is unauthenticated with no payload size cap (`event_timeline` is an
unbounded list). Consistent with the existing LAN-only posture (`/scan` accepts 25 MB, `/wines`
is open), so it's fine for self-host on a trusted network. Before exposing the backend beyond a
trusted LAN, add: a `max_length` on `event_timeline`, a request body size guard, a `scan_id`
charset/length validator (it is a client-controlled upsert key), and auth/rate-limiting on the
telemetry routes. `GET` and (v0.3.0.0) `DELETE /telemetry/scans` mirror the `TELEMETRY_ENABLED`
gate and `GET` tolerates a corrupt row; the new unauthenticated `DELETE` (bulk wipe) is part of
the accepted LAN posture but is the most destructive verb here — gate it first when exposing
the backend beyond a trusted LAN.

---

## E7: Web design system documentation

Document the web curator's emergent color/typography/component system in DESIGN.md alongside the existing iOS tokens. New contributors currently derive web patterns from reading App.tsx/WineCard.tsx rather than a spec, which risks drift.

---

## E8: Keyboard navigation in ImageCandidatePicker grid

Add arrow-key navigation (←→↑↓) between candidates in the expanded 3x3 picker grid. Tab-only navigation works but is slow for power curators doing batch image curation.

---

## Completed

- **E18** — WineListViewModel test coverage + raised the iOS gate floor. Added 13 tests driving `scan()` through `MockURLProtocol` SSE bodies, covering the `performScan` event loop (wine/image/notes/error/complete/status/ping, dedup, no-wines fallback), the image placeholder/ready paths, `clear()`, and the `brave_key`-false health branch. `WineListViewModel` went 14.6% → 92.1%; the logic-core pool went 52.1% → 85.4%. Raised the E16 gate floor 50% → 80% to lock it in. **Completed:** v0.3.2.1 (2026-06-25)
- **E17** — Pre-backend-split documentation rot resolved. Rewrote the docs that still described the in-app monolith to the iOS + backend reality: `architecture.md` (overview diagram, SSE event protocol, backend extraction/image/sommelier sections), `configuration.md` (backend env vars + iOS runtime settings, dropped the stale in-app hardcoded-settings table), `wine-schema.md` (canonical `shared/wine-schema.json`, backend prompt + parse path), `evaluate-extraction.md` (now the `backend/tests/eval_extraction.py` integration eval), plus dangling `BraveSearchClient.swift` references in `design-decisions.md` and `validate-brave-hitrate.md`. (first-scan.md + camera sections were done in v0.3.1.1.) **Completed:** v0.3.2.0 (2026-06-25)
- **E16** — iOS coverage gate re-established. Recalibrated the exclusion set to the logic core the XCTest suite actually exercises (Backend/Models/ViewModels/StartupValidator), which pools to 52.1% vs 10.1% for the whole target. CI now runs `xcodebuild test` with `-enableCodeCoverage`, extracts coverage via `xcrun xccov ... --json`, and `Scripts/ios-coverage-gate.sh` enforces a 50% floor (regression ratchet, raise as the suite grows — `WineListViewModel` is the main gap at ~15%). **Completed:** v0.3.2.0 (2026-06-25)
- **E14** — Telemetry listing index added. `GET /telemetry/scans` sorts by `timestamp` (now indexed) and filters by `outcome`; added a standalone `timestamp` index for the default newest-first listing and a composite `(outcome, timestamp)` for the filtered path, dropping the now-redundant standalone `outcome` index (folded into the composite's leading column). Indexes declared on the model (new DBs) + idempotent `CREATE INDEX IF NOT EXISTS` / `DROP INDEX IF EXISTS` DDL in `init_db()` (existing DBs), with 4 new tests. **Completed:** v0.3.2.0 (2026-06-25)
- **E15** — iOS dual-tree divergence resolved: deleted the macOS mirror (`Sources/`, `Tests/`, root `Package.swift`, entitlements) — iOS is now the only Swift client — and adopted XcodeGen. `ios/VisualWinelistIOS.xcodeproj` is generated from `ios/project.yml` (git-ignored), so a new source file can no longer be forgotten from a hand-maintained pbxproj file list (the bug that broke device builds twice). CI installs XcodeGen + generates before building; `make project` for local dev. Follow-ups filed as E16 (coverage gate) and E17 (doc rot). **Completed:** v0.3.1.0 (2026-06-24)
- **E13** — Scan-image retention policy: per-request opt-in save + `X-Scan-Image-Retention` prune, always bounded by `SCAN_IMAGE_RETENTION_DEFAULT` so "save" can't grow disk without end. **Completed:** v0.3.0.0 (2026-06-24)
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
