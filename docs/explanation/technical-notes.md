# Technical Notes: Why Ollama Runs Natively

## The short version

Docker Compose starts FastAPI only. Ollama must run natively on your Mac. This is intentional.

## Why Ollama is excluded from Docker Compose

Ollama needs GPU access to run the `qwen3-vl:8b` vision model at usable speed. On macOS, this means Apple Metal. The performance difference is dramatic:

| Runtime | Inference speed | Time for first wine event |
|---|---|---|
| Native (`ollama serve`) | ~50 tokens/sec (Metal) | 3–7 s |
| Docker container | ~3–5 tokens/sec (CPU only) | 60–120 s |

Docker Desktop on macOS does not pass through the Metal GPU to containers. Running Ollama inside Docker on a Mac degrades it to CPU-only inference, which makes the 10-second first-bottle target impossible.

Linux hosts with a discrete GPU can run Ollama in Docker (with `--gpus all` and the NVIDIA container toolkit), but this is not the primary deployment target for v2.

## How the API container reaches Ollama

The FastAPI container uses `host.docker.internal:11434` to reach Ollama running on the host. This is a Docker Desktop feature on macOS and Windows — the special hostname resolves to the host machine's loopback address.

```
┌──────────────────────────────────────┐
│ Docker Desktop (macOS)               │
│  ┌────────────────────────────────┐  │
│  │ api container                  │  │
│  │  OLLAMA_BASE_URL=              │  │
│  │  http://host.docker.internal   │  │  ──→  localhost:11434
│  │  :11434                        │  │       (ollama serve, native)
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

On a Linux host (no Docker Desktop), replace `host.docker.internal` with the host's LAN IP or use `network_mode: host` in `docker-compose.yml`.

## Data persistence

Two directories are mounted into the container:

| Host path | Container path | Contains |
|---|---|---|
| `./image-cache/` | `/cache` | Downloaded bottle images (JPEG) |
| `./data/` | `/data` | SQLite cache database (`cache.db`) |

Both directories are created automatically on first `docker compose up`. The `IMAGE_CACHE_DIR` and `DATABASE_URL` env vars point to these paths inside the container.

## Running the stack

```bash
# 1. Start Ollama (if not already running)
ollama serve

# 2. Pull the model (first time only, ~5GB download)
ollama pull qwen3-vl:8b

# 3. Set your Brave Search API key
export BRAVE_API_KEY=your_key_here

# 4. Start the API container
docker compose up

# 5. Verify
curl http://localhost:8000/health
# → {"status":"ok","ollama":true,"brave_key":true}
```

## Health check

`GET /health` reports backend status. The API starts even if Ollama is unreachable — it will return `{"status":"degraded","ollama":false}` until `ollama serve` is running. Clients should poll `/health` on launch and surface a setup prompt if `ollama` is `false`.

## Deployment for internet access

v2 is designed for personal/home network use. For internet-facing deployments (sharing with family, restaurant staff), put the API behind a reverse proxy with HTTPS. See `docs/deployment/https-setup.md` (T15) for an nginx configuration.

The default setup has no authentication — anyone on the same network can access the curator UI and modify the cache. This is acceptable for home network use. For shared environments, deploy behind an auth proxy or VPN.
