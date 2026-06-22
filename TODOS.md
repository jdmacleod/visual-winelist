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

## Security: CI gitleaks full-history scan

The pre-commit hook blocks new secrets in local commits but can be bypassed with
`--no-verify` or a direct GitHub web/API push. Add a `gitleaks detect --source .`
job to `.github/workflows/ci.yml` that scans full history on every PR.

---

## SSE: lineBuffer memory cap in BackendClient.swift

The byte-iteration loop in `BackendClient.scan()` accumulates bytes in `lineBuffer`
with no capacity limit. A misbehaving backend or misconfigured proxy flushing a
multi-MB response as a single line would cause unbounded `Data` growth until OOM
or connection close. Fix: add a hard cap (e.g. 1 MB) that discards oversized
pseudo-lines and continues.

---

## SSE: iOS UTF-8 chunk boundary issue in IOSScanSession.swift

`didReceive data:` decodes the full `Data` chunk to `String` before line
splitting. If a URLSession delivery boundary falls mid-multibyte character (e.g.
an accented wine name), the entire chunk is silently dropped — potentially
several complete SSE events. Fix: accumulate raw `Data` in `lineBuffer` and
decode per-line after splitting on `0x0A`, matching `BackendClient.swift`.

---

## Security: JPEG magic-byte validation on image upload

`POST /wines/{id}/image` rejects non-JPEG `Content-Type` headers but does not
validate actual file magic bytes. A client can send any binary with
`Content-Type: image/jpeg`. Fix: check `data[:2] == b'\xff\xd8'` before writing.

---

## Performance: Collapse verified_total COUNT into main search query

`GET /wines/search` runs two DB round-trips per request: one for results, one
for `verified_total`. Replace with a single query using conditional aggregation:
`count(*) FILTER (WHERE verified = TRUE)` so `verified_total` comes back in the
same query.

---

## UX: Per-wine `notesIncomplete` tracking

`notesIncomplete` is scan-session-scoped: set to `true` when the SSE stream
closes without `event:complete`. Wines in the cache that never had sommelier
notes generated (Ollama was unavailable at scan time) also show `tasting_note = nil`
but would not show the "connection dropped" banner. Consider per-wine incomplete
tracking so cached wines with no notes show a distinct "notes unavailable" state
rather than appearing identical to freshly-scanned wines that got notes.

---

## Security: Pin Docker base image digests

`FROM python:3.13-slim` and `COPY --from=ghcr.io/astral-sh/uv:latest` are floating
tags. Pin both to specific SHA256 digests (or a semver for uv) for reproducible,
supply-chain-safe builds.

---

## URLError mapping incomplete in BackendClient.swift

`BackendClient.scan()` maps `.cannotConnectToHost`, `.networkConnectionLost`,
`.cannotFindHost`, and `.timedOut` to `BackendError.unreachable`, but misses
`.notConnectedToInternet` and `.secureConnectionFailed`. Both are common on
mobile (airplane mode, expired TLS cert). Fix: add both codes to the `where`
clause in the `URLError` catch.

---

## Tests: MockURLProtocol static var race condition

`MockURLProtocol.handler` is a static `var` set in `setUp()` and cleared in
`tearDown()`. If two `XCTestCase` instances were ever run in parallel, handlers
would bleed across tests. `@unchecked Sendable` on `MockURLProtocol` suppresses
the Swift concurrency check. Fix: use an actor-isolated registry keyed by
`ObjectIdentifier(self)` or enable the `SWIFT_TEST_PARALLEL` guard.

---

## iOS: BackendClient health/image not session-injectable

`ios/Sources/VisualWinelistIOS/Backend/BackendClient.swift` uses `URLSession.shared`
for `checkHealth()` and `fetchImage(wineId:)`. Only `scan()` is testable via
`IOSScanSession.make(configuration:)`. Fix: add `let session: URLSession = .shared`
to the iOS `BackendClient` struct and replace the `URLSession.shared` call sites
with `self.session`, matching the macOS pattern.

---

## Web: sort=verified not in TypeScript SortOption type

`backend/backend/routers/scan.py` accepts `sort=verified` but `web/src/types/wine.ts`
`SortOption` type only covers the other sort options. Add `"verified"` to the
`SortOption` union type and wire it to the curator UI filter bar.

---

## Backend: `_scanning` global is process-local (single-worker constraint)

`_scanning` in `scan.py` is a module-level bool. Each uvicorn worker process has its
own copy, so `--workers N > 1` allows simultaneous scans against a single Ollama
instance. Fix: either document the single-worker constraint prominently and add a
startup assertion, or replace the in-process bool with a cross-process advisory lock
(e.g. filesystem lock or Redis SETNX).

---

## Swift: `imageTasks` array grows unboundedly within a scan

Both macOS and iOS `WineListViewModel.imageTasks` append a `Task` per wine image event
but never prune completed entries. For a 100-wine scan the array holds 100 completed
`Task` references until `clear()` or `cancelScan()`. Fix: remove completed tasks from
the array in `handleImageEvent` after the closure finishes (e.g. `imageTasks.removeAll
{ $0.isCancelled }` at the top of each image event handler).

---

## CI: Swift coverage gate fails silently on `llvm-cov` error

The CI step that measures Swift coverage uses `xcrun llvm-cov report … || echo
"::warning::…"`. If `llvm-cov` fails for any reason (wrong binary, mismatched LLVM
version), the step exits 0, `TOTAL` stays empty, and the coverage threshold check is
skipped with no build failure. Fix: treat a missing or unparseable `llvm-cov` output
as a gate failure rather than a warning when `PROFDATA` and `XCTEST` are present.

---

## Backend: `BackendClient.scan()` inner Task not cancelled on consumer cancel

`BackendClient.scan()` creates an unstructured `Task { }` inside the
`AsyncThrowingStream` closure. When the `for-try-await` consumer is cancelled, the
inner `Task` keeps the `URLSession` connection open until the server closes it (up to
the configured `timeoutInterval`). A rapid scan→cancel→scan sequence can hit the 503
`SCANNER_BUSY` gate. Fix: use `withTaskCancellationHandler` to cancel the inner task
when the stream consumer is cancelled, or switch to structured concurrency so the inner
task inherits the consumer's cancellation.

---
