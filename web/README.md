# visual-winelist curator

React/TypeScript web app for curating the wine image cache. Search cached wines, verify the best bottle image for each, and mark records as curator-verified.

## Quick start (Docker)

```bash
# From the repo root — starts the backend and curator together:
docker compose --profile curator up
```

The curator is served at `http://localhost`. All API calls (`/wines`, `/curate`, `/health`, `/scan`) are proxied to the backend container by nginx — no separate URL configuration needed.

## Development (hot reload)

Requires Node.js 22+ and a running backend (`docker compose up` or `uv run uvicorn ...`).

```bash
cd web
npm install
npm run dev      # Vite dev server at http://localhost:5173
```

API calls are proxied to `http://localhost:8000` in development (configured in `vite.config.ts`). No CORS issues.

## Production build (manual)

```bash
npm run build    # outputs to dist/
```

Serve `dist/` as static files behind nginx. The `nginx.conf` in this directory is the reference config — it handles SPA routing and proxies all API routes including SSE streaming for `/scan`. See [docs/deployment/https-setup.md](../docs/deployment/https-setup.md) for HTTPS setup.

## Lint

```bash
npx prettier --check "src/**/*.{ts,tsx,css}"
npx eslint --max-warnings 0 src
```
