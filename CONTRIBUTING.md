# Contributing

## Repository layout

```
backend/   FastAPI service (Python/uv)
Sources/   macOS SwiftUI client (Swift package at repo root)
ios/       iOS SwiftUI client (separate Swift package)
web/       React/TypeScript curator UI (npm)
```

Each component has its own build and test commands. CI (`.github/workflows/ci.yml`) runs lint and tests for all four on every push and PR to `main`.

## Backend (Python)

```bash
cd backend
uv sync --group dev    # ruff, mypy
uv sync --extra dev    # pytest, httpx

uv run ruff format backend/ tests/   # auto-fix formatting
uv run ruff check backend/ tests/    # lint
uv run mypy backend/                 # type check
uv run pytest -m "not integration"   # unit tests (no live services required)
```

Integration tests require a running backend and Ollama:

```bash
BACKEND_URL=http://localhost:8000 uv run pytest -m integration -v -s
```

## macOS client (Swift)

```bash
swift build
swift test
swift format lint -r --configuration .swift-format Sources Tests Scripts
swift format -i -r --configuration .swift-format Sources Tests Scripts   # auto-fix
```

The macOS client requires `BACKEND_URL` set to a running backend (`http://localhost:8000` by default).

## iOS client (Swift)

```bash
cd ios
swift build --sdk $(xcrun --sdk iphonesimulator --show-sdk-path) --triple arm64-apple-ios16.0-simulator
```

For device builds, open `ios/Package.swift` in Xcode and run on a connected iPhone (iOS 16+).

## React curator (TypeScript)

```bash
cd web
npm install
npm run dev                                        # dev server at localhost:5173
npx prettier --check "src/**/*.{ts,tsx,css}"      # check formatting
npx prettier --write "src/**/*.{ts,tsx,css}"      # auto-fix
npx eslint --max-warnings 0 src                   # lint
npm run build                                     # production build (runs tsc + vite)
```

## Making changes

- Keep PRs focused — one logical change per PR.
- If you change `backend/backend/prompts/wine_extraction.py`, run the extraction eval against representative photos and note before/after metrics in your PR:
  ```
  BACKEND_URL=http://localhost:8000 uv run pytest -m integration tests/eval_extraction.py -v -s
  ```
- If you change ranking/filtering logic in `backend/backend/services/brave_client.py`, run the Brave hit-rate validation:
  ```
  BRAVE_API_KEY=your_key uv run pytest -m integration tests/validate_brave_hitrate.py -v -s
  ```
- **WineObject schema** is defined in three places: `Sources/VisualWinelist/Models/WineObject.swift` (macOS), `ios/Sources/VisualWinelistIOS/Models/WineObject.swift` (iOS), `backend/backend/models/wine.py` (Python), and `web/src/types/wine.ts` (TypeScript). Adding a field requires updating all four. CI does not currently enforce schema sync — check manually.
- See [docs/explanation/](docs/explanation/) for architecture and design reasoning before changing core flows (SSE streaming, Ollama pre-fill, Brave ranking, two-phase sommelier).

## Cutting a release

1. Bump `VERSION` and `CHANGELOG.md`.
2. Update the static "Latest release" badge in `README.md`.
3. Bump `version` in `backend/pyproject.toml`.
4. Tag and push: `git tag v0.x.0 && git push --tags`.

## Reporting issues

Use the bug report or feature request issue templates. For extraction/image-quality bugs, include the wine list photo if possible — it's the fastest way to reproduce and diagnose.
