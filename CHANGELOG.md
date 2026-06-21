# Changelog

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
