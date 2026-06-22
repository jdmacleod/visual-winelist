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

## P1: Swift Cancel UX — withThrowingTaskGroup image task stall

When the user taps Cancel mid-scan, `cancelScan()` cancels the URLSession (SSE stream
throws → group body throws → Swift cancels child image tasks). Because `handleImageEvent`
now re-throws CancellationError, children propagate cleanly. However, the broader cancel
path still relies on the URLSession cancel → SSE throw chain. Consider wrapping `performScan()`
in an explicit Swift `Task` stored as a property so that `cancelScan()` can call
`task.cancel()` directly, ensuring all child tasks are cancelled immediately via structured
concurrency rather than relying on the URLSession error propagation chain.

---


## P1: HTTP 415 INVALID_IMAGE not surfaced to user

When the backend rejects a scan with HTTP 415 (non-JPEG magic bytes), both iOS and macOS
`BackendClient` map it to `BackendError.httpError(415)`, which falls through to the
generic "Scan failed" error message. Add a dedicated `BackendError.invalidImage` case and
handle it in both ViewModels to show an actionable message: "Image format not supported —
use JPEG. Try taking a photo directly rather than importing."

---

## UX: Per-wine `notesIncomplete` tracking

`notesIncomplete` is scan-session-scoped: set to `true` when the SSE stream
closes without `event:complete`. Wines in the cache that never had sommelier
notes generated (Ollama was unavailable at scan time) also show `tasting_note = nil`
but would not show the "connection dropped" banner. Consider per-wine incomplete
tracking so cached wines with no notes show a distinct "notes unavailable" state
rather than appearing identical to freshly-scanned wines that got notes.

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
- **Closed (already done in v0.2.4.2)** — URLError mapping incomplete in BackendClient.swift (`.notConnectedToInternet` + `.secureConnectionFailed` were already in the macOS scan() catch)
- **Closed (not worth complexity)** — Performance: Collapse `verified_total` COUNT into main search query (two queries are intentionally different; FILTER clause merge adds complexity for unmeasurable gain at SQLite personal-use scale)
