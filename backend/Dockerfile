FROM python:3.13-slim@sha256:3a2c25932e66f706172de831a1b283d491c53ef876cd7fc55a62bcf9a6dd2c61

COPY --from=ghcr.io/astral-sh/uv:latest@sha256:bf915f572feae763546ada06364f5369305195b33a258a44ae70cbd7e1777a31 /uv /usr/local/bin/uv

WORKDIR /app

# Install dependencies before copying source for layer-cache efficiency.
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen

COPY backend/ ./backend/

# Run as non-root to limit blast radius of a future RCE vulnerability.
# UID 1001 is pinned so host volume chown instructions stay stable across
# base-image rebuilds. On Linux hosts, pre-create the volume directories
# with matching ownership before starting:
#   sudo chown -R 1001:1001 ./image-cache ./data
# macOS Docker Desktop bridges ownership automatically.
RUN adduser --system --no-create-home --uid 1001 appuser \
    && chown -R appuser /app
ENV UV_NO_CACHE=1
USER appuser

EXPOSE 8000

# Single worker required: _scanning is a module-level bool in scan.py, so multiple
# workers would each maintain their own copy, allowing concurrent scans against a
# single Ollama instance. --workers 1 enforces the constraint at the process level.
CMD ["uv", "run", "uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
