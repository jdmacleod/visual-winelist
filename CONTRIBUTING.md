# Contributing

## Repository layout

```
backend/   FastAPI service (Python/uv)
ios/       iOS SwiftUI client (.xcodeproj generated from project.yml via XcodeGen)
web/       React/TypeScript curator UI (npm)
```

Each component has its own build and test commands. CI (`.github/workflows/ci.yml`) runs lint and tests for all three on every push and PR to `main`.

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

## iOS client (Swift)

The `.xcodeproj` is generated from `ios/project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) and is not committed. Run `make project` after cloning, and again whenever you add, rename, or remove a source file.

```bash
make project          # cd ios && xcodegen generate
swift format lint -r --configuration .swift-format ios/Sources ios/Tests Scripts
swift format -i -r --configuration .swift-format ios/Sources ios/Tests Scripts   # auto-fix

# Device compile (no signing):
cd ios && xcodebuild build -project VisualWinelistIOS.xcodeproj -scheme VisualWinelistIOS \
  -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO
```

Unit tests run via the SwiftPM package on a simulator (the xcodeproj shadows the package, so move it aside first):

```bash
cd ios
mv VisualWinelistIOS.xcodeproj /tmp/_vwl && \
  xcodebuild test -scheme VisualWinelistIOS \
    -destination "platform=iOS Simulator,name=iPhone 16" CODE_SIGNING_ALLOWED=NO; \
  mv /tmp/_vwl VisualWinelistIOS.xcodeproj
```

For device runs, `make ios-open` and run on a connected iPhone (iOS 17+). The app requires `BACKEND_URL` (entered on first launch) pointing at a running backend.

## React curator (TypeScript)

**Docker (serves a production build):**

```bash
docker compose --profile curator up   # http://localhost
```

**Local dev server (hot reload, recommended for curator UI work):**

```bash
cd web
npm install
npm run dev                                        # dev server at localhost:5173
npx prettier --check "src/**/*.{ts,tsx,css}"      # check formatting
npx prettier --write "src/**/*.{ts,tsx,css}"      # auto-fix
npx eslint --max-warnings 0 src                   # lint
npm run build                                     # production build (runs tsc + vite)
```

## Environment setup

Copy `.env.example` to `.env` and restrict its permissions before adding your API key:

```bash
cp .env.example .env
chmod 600 .env   # prevents other local users/processes from reading your keys
```

`.env` is gitignored and must never be committed. The pre-commit hooks include a
secret scanner (gitleaks) that will block accidental key commits.

### Docker volume ownership (Linux hosts only)

The backend container runs as UID 1001. On Linux, Docker creates bind-mount
directories as root on first `docker compose up`. Pre-create them with matching
ownership so the container can write to them:

```bash
mkdir -p image-cache data
sudo chown -R 1001:1001 image-cache data
```

macOS Docker Desktop handles this transparently — no action needed.

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
- **WineObject schema** is defined in `shared/wine-schema.json` (canonical) and mirrored in three files: `ios/Sources/VisualWinelistIOS/Models/WineObject.swift` (iOS), `backend/backend/models/wine.py` (Python), and `web/src/types/wine.ts` (TypeScript). Adding or renaming a field requires updating all four. CI runs `tests/test_schema_sync.py` which verifies the Python model matches `wine-schema.json` automatically; Swift and TypeScript must be checked manually.
- See [docs/explanation/](docs/explanation/) for architecture and design reasoning before changing core flows (SSE streaming, Ollama pre-fill, Brave ranking, two-phase sommelier).

## Cutting a release

1. Bump `VERSION` and `CHANGELOG.md`.
2. Update the static "Latest release" badge in `README.md`.
3. Bump `version` in `backend/pyproject.toml`.
4. Tag and push: `git tag v0.x.0 && git push --tags`.

## Reporting issues

Use the bug report or feature request issue templates. For extraction/image-quality bugs, include the wine list photo if possible — it's the fastest way to reproduce and diagnose.
