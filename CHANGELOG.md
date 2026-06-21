# Changelog

## v0.2.4.1 (2026-06-21)

### Fixed

- **SSE stream-end without trailing blank line** — `BackendClient.scan()` now calls
  `parser.feed(line: "")` after flushing the line buffer, dispatching any pending SSE event
  when the server closes the connection without a trailing `\n\n`. Previously the last wine
  event could be silently dropped on truncated streams.

### Changed

- **`BackendClient` injectable `URLSession`** — the initializer now accepts an optional
  `session: URLSession` parameter (default `.shared`), enabling unit tests to inject a
  `MockURLProtocol`-backed session without a live server.
- **Coverage thresholds enforced** — vitest now fails if React statement coverage drops below
  80%; pytest fails if Python line coverage drops below 80%. Current baselines: React 87%,
  Python 89%.
- **CI: `web-test` job guard** — the TypeScript test job now skips gracefully when
  `web/package.json` is absent, matching the existing `web-lint` guard pattern.

### Tests

- React vitest suite: 48 tests (was 34) — added `Pagination` component tests (5) and
  `App` error-path tests for `searchWines` rejection and `deleteWine` rejection (2).
- Swift XCTest: 41 tests (was 38) — added `BackendClient` tests for `fetchImage()` 200/404
  responses and `URLError.cannotConnectToHost` → `BackendError.unreachable` mapping.
- iOS test target placeholder changed from `XCTAssertTrue(true)` to
  `XCTSkip("iOS test target placeholder — real tests tracked in T9/T10")`.

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
