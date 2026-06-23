# Visual Winelist

[![CI](https://github.com/jdmacleod/visual-winelist/actions/workflows/ci.yml/badge.svg)](https://github.com/jdmacleod/visual-winelist/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/badge/release-v0.2.10.0-blue.svg)](https://github.com/jdmacleod/visual-winelist/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 14+ · iOS 16+](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20iOS%2016%2B-lightgrey.svg)](https://github.com/jdmacleod/visual-winelist)
[![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![Python 3.12+](https://img.shields.io/badge/python-3.12%2B-blue.svg)](https://python.org)

Point a camera at a restaurant wine list and watch bottle images appear — one by one as each wine is identified — on your Mac or iPhone.

## What this is

A service-architecture wine scanner. A FastAPI backend handles the heavy lifting (Qwen3-VL extraction via Ollama, Brave image search, shared caching), and native clients send a photo and stream results back:

```
iPhone / Mac camera
        │
        │  POST /scan (JPEG)
        ▼
┌──────────────────────────────────────────────┐
│  FastAPI backend                             │
│                                              │
│  Qwen3-VL (Ollama) → extracts wine text      │
│  Brave Image Search → finds bottle photos    │
│  SQLite cache      → skips repeat lookups   │
│  Sommelier (Ollama) → adds tasting notes    │
└──────────────────────────────────────────────┘
        │
        │  SSE stream (wine events + image events + notes)
        ▼
SwiftUI grid: bottles appear as they're found
        │
        ▼
┌──────────────────┐
│  React curator   │  (web UI — search cache, verify best image)
└──────────────────┘
```

## Repository layout

```
backend/   FastAPI service — extraction, image search, cache, sommelier
Sources/   macOS SwiftUI client (Swift package at repo root)
ios/       iOS SwiftUI client
web/       React/TypeScript curator UI
docs/      Documentation (tutorial, how-to, reference, explanation)
Scripts/   Standalone eval scripts (Swift)
resources/ Eval images and reference data
```

## Privacy

Your wine list photo is sent to **your self-hosted backend server** — not a third-party cloud service. Only you control where the backend runs and who can reach it. Extracted wine names are sent to Brave Search to find bottle images; Brave does not receive the original photo. See [docs/explanation/design-decisions.md](docs/explanation/design-decisions.md) for the full reasoning.

## Requirements

**Backend (required by all clients):**
- [Docker](https://docker.com) + Docker Compose, or Python 3.12+ with [uv](https://docs.astral.sh/uv/)
- [Ollama](https://ollama.com) running natively with `qwen3-vl:8b` pulled
- A [Brave Search API](https://brave.com/search/api/) key (free tier)

**macOS client:**
- macOS 14+

**iOS client:**
- iOS 16+ (physical device recommended — camera required)
- Backend reachable over local Wi-Fi

**React curator:**
- Node.js 22+ for development; any web browser to use

## Quick start

### 1. Start the backend

```bash
ollama pull qwen3-vl:8b
ollama serve

# in a second terminal, from the repo root:
BRAVE_API_KEY=your_key docker compose up
```

Verify: `curl http://localhost:8000/health` → `{"status":"ok",...}`.

See [backend/README.md](backend/README.md) for full configuration options and running without Docker.

### 2. macOS client

```bash
export BACKEND_URL=http://localhost:8000
swift run
```

Or open `Package.swift` in Xcode and run the `VisualWinelist` scheme.

### 3. iOS client

On first launch, enter your Mac's LAN IP as the backend URL (e.g. `http://192.168.1.100:8000`). Find it on the Mac with `ipconfig getifaddr en0`. Both devices must be on the same Wi-Fi network.

See [ios/README.md](ios/README.md) for build instructions.

### 4. React curator

**With Docker (recommended):**

```bash
docker compose --profile curator up
```

Opens at `http://localhost`. The curator container proxies all API calls to the backend container — no extra configuration needed.

**Without Docker (development):**

```bash
cd web
npm install
npm run dev    # open http://localhost:5173
```

API calls are proxied to `http://localhost:8000` via Vite (configured in `vite.config.ts`).

See [web/README.md](web/README.md) for more options.

## Usage

1. Grant camera access when prompted.
2. Point the camera at a wine list and tap to capture.
3. Watch bottle images fill the grid as wines are identified. Tasting notes and pairings appear after the initial pass.
4. Tap any bottle for full details: tasting note, pairings, producer, region, confidence score.
5. Use **Scan more** to photograph additional pages (new wines are appended; duplicates by name+vintage are skipped). Use **Clear** to start over.
6. Open the React curator (`http://localhost:5173`) to search the cache and mark images as verified.

## Documentation

- [Tutorial: scan your first wine list](docs/tutorial/first-scan.md)
- [How-to: evaluate extraction quality](docs/how-to/evaluate-extraction.md)
- [How-to: validate Brave image search hit rate](docs/how-to/validate-brave-hitrate.md)
- [Reference: wine extraction JSON schema](docs/reference/wine-schema.md)
- [Reference: configuration](docs/reference/configuration.md)
- [Explanation: architecture & data flow](docs/explanation/architecture.md)
- [Explanation: design decisions](docs/explanation/design-decisions.md)
- [Deployment: HTTPS setup with nginx](docs/deployment/https-setup.md)

## Development

### Backend (Python)

```bash
cd backend
uv sync --group dev && uv sync --extra dev
uv run ruff format backend/ tests/
uv run ruff check backend/ tests/
uv run mypy backend/
uv run pytest -m "not integration"        # unit tests
uv run pytest -m integration -v -s        # requires live backend + Ollama
```

### macOS client (Swift)

```bash
swift build
swift test
swift format lint -r --configuration .swift-format Sources Tests Scripts
```

### iOS client (Swift)

```bash
cd ios
swift build --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios16.0-simulator
```

### React curator (TypeScript)

```bash
cd web
npm install
npx prettier --check "src/**/*.{ts,tsx,css}"
npx eslint --max-warnings 0 src
npm run build
```

### Eval scripts

```bash
# Extraction quality (requires running backend + Ollama + images in resources/images/)
cd backend
BACKEND_URL=http://localhost:8000 uv run pytest -m integration tests/eval_extraction.py -v -s

# Brave image hit rate (requires BRAVE_API_KEY)
BRAVE_API_KEY=your_key uv run pytest -m integration tests/validate_brave_hitrate.py -v -s

# Original Swift scripts (call Ollama directly, no backend required)
swift Scripts/eval-extraction.swift
BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift
```

See [resources/README.md](resources/README.md) for populating eval images.
