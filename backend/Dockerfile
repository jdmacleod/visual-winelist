FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

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

CMD ["uv", "run", "uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
