FROM python:3.13-slim@sha256:c33f0bc4364a6881bed1ec0cc2665e6c53c87a43e774aaeab88e6f17af105e4f

COPY --from=ghcr.io/astral-sh/uv:latest@sha256:d0a0a753ab981624b49c97abc98821c1c09f4ca69d1ef5cee69c501be3d88479 /uv /usr/local/bin/uv

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
