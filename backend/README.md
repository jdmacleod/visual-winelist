# visual-winelist backend

FastAPI service that handles wine list extraction (Ollama/Qwen3-VL), bottle image search (Brave), and shared caching. macOS and iOS clients POST a JPEG and receive wines + images via a Server-Sent Events stream.

## Requirements

- Python 3.12+
- [uv](https://docs.astral.sh/uv/) (`brew install uv`)
- [Ollama](https://ollama.com) running natively with `qwen3-vl:8b` pulled:
  ```
  ollama pull qwen3-vl:8b
  ollama serve
  ```
- A [Brave Search API](https://brave.com/search/api/) key (free tier)

## Quick start

```bash
cd backend
cp .env.example .env          # then fill in BRAVE_API_KEY
uv sync
uvicorn backend.main:app --reload --workers 1
```

> **Note:** Always run with `--workers 1`. The backend shares a single Ollama session; multiple workers would allow concurrent scans against the same model instance, causing interleaved output.

Or with Docker Compose (from the repo root):

```bash
BRAVE_API_KEY=your_key docker compose up
```

The API is available at `http://localhost:8000`. Check `GET /health`.

## Configuration

| Env var | Default | Description |
|---|---|---|
| `BRAVE_API_KEY` | — | Brave Search API key (required for image search) |
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Ollama server URL |
| `OLLAMA_MODEL` | `qwen3-vl:8b` | Vision model to use for extraction |
| `IMAGE_CACHE_DIR` | `./image-cache` | Directory for cached bottle images |
| `MAX_UPLOAD_SIZE` | `26214400` (25 MB) | Max photo upload size in bytes |

> **Why Ollama runs natively (not in Docker):** Docker Desktop on macOS does not support GPU passthrough. Ollama's inference degrades severely without Metal/GPU access. See [technical-notes.md](../technical-notes.md).

## API

| Method | Path | Description |
|---|---|---|
| `POST` | `/scan` | Upload a JPEG, receive wines + images via SSE. Returns HTTP 415 `{"code":"INVALID_IMAGE"}` if the file is not a valid JPEG (magic bytes checked). |
| `GET` | `/health` | Backend and Ollama status. Returns `{status, ollama, brave_key, version}`. |
| `GET` | `/wines/search` | Paginated wine search (`?q=&page=&page_size=&sort=&order=&status=`) |
| `GET` | `/wines/{id}/image` | Serve cached bottle image |
| `DELETE` | `/wines/{id}` | Remove a wine from the cache |
| `POST` | `/curate` | Mark a wine as curator-verified |

## Development

```bash
uv sync --group dev    # install lint tools
uv sync --extra dev    # install test dependencies

uv run ruff format backend/ tests/
uv run ruff check backend/ tests/
uv run mypy backend/
uv run pytest -m "not integration"        # unit tests (no live services)
uv run pytest -m integration -v -s        # integration tests (requires running backend + Ollama)
```
