# visual-winelist curator

React/TypeScript web app for curating the wine image cache. Search cached wines, verify the best bottle image for each, and mark records as curator-verified.

## Requirements

- Node.js 22+ and npm
- A running visual-winelist backend

## Development

```bash
cd web
npm install
npm run dev      # Vite dev server at http://localhost:5173
```

API calls are proxied to `http://localhost:8000` in development (configured in `vite.config.ts`). No CORS issues.

## Production build

```bash
npm run build    # outputs to dist/
```

Serve `dist/` as static files behind nginx. Configure nginx to proxy `/wines`, `/curate`, `/health`, and `/scan` to the FastAPI backend. See [docs/deployment/https-setup.md](../docs/deployment/https-setup.md) for a complete nginx config.

## Lint

```bash
npx prettier --check "src/**/*.{ts,tsx,css}"
npx eslint --max-warnings 0 src
```
