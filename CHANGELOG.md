# Changelog

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
