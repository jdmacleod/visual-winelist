# HTTPS setup for internet-facing deployments

The default setup runs the backend over HTTP on port 8000, which is fine on a trusted home LAN. If you expose the backend to the internet (so you can use the iOS app away from home Wi-Fi), you need HTTPS — otherwise your wine list photos travel in cleartext.

This guide sets up nginx as a reverse proxy in front of the FastAPI backend.

## Prerequisites

- A server with a public IP and a domain name pointing to it
- `docker compose up` already working (backend on `localhost:8000`)
- `certbot` (Let's Encrypt) installed: `apt install certbot python3-certbot-nginx`

## Step 1 — Install nginx

```
apt install nginx
```

## Step 2 — Basic nginx config (HTTP, pre-certificate)

Create `/etc/nginx/sites-available/visual-winelist`:

```nginx
server {
    listen 80;
    server_name YOUR_DOMAIN;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Temporary redirect while obtaining cert
    location / {
        return 301 https://$host$request_uri;
    }
}
```

Enable it:

```
ln -s /etc/nginx/sites-available/visual-winelist /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx
```

## Step 3 — Obtain a certificate

```
certbot --nginx -d YOUR_DOMAIN
```

Certbot edits the nginx config and reloads automatically. If you prefer manual control, use `certonly`:

```
certbot certonly --webroot -w /var/www/certbot -d YOUR_DOMAIN
```

## Step 4 — Full nginx config (HTTPS + API proxy + React curator)

Replace the nginx config with the full version:

```nginx
server {
    listen 80;
    server_name YOUR_DOMAIN;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name YOUR_DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    # Long-lived SSE connections — do not buffer or time out prematurely
    proxy_buffering    off;
    proxy_read_timeout 600s;

    # API — proxy to FastAPI backend
    location ~ ^/(scan|health|wines|curate) {
        proxy_pass         http://localhost:8000;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;

        # SSE: disable nginx buffering so events reach the client immediately
        proxy_cache        off;
        proxy_http_version 1.1;
        proxy_set_header   Connection "";
    }

    # React curator — serve from pre-built static files
    location / {
        root  /var/www/visual-winelist;
        index index.html;
        try_files $uri $uri/ /index.html;  # SPA routing
    }
}
```

## Step 5 — Deploy the React curator static files

```bash
cd web
npm ci
npm run build
rsync -av dist/ user@YOUR_SERVER:/var/www/visual-winelist/
```

Or add a `Makefile` target / CI step that runs the build and copies `dist/` to the server.

## Step 6 — Auto-renew certificates

Certbot installs a systemd timer. Verify it:

```
systemctl status certbot.timer
```

Test renewal without actually renewing:

```
certbot renew --dry-run
```

## Step 7 — Update client URLs

- **iOS app**: Go to Settings → Visual Winelist → Backend URL → set `https://YOUR_DOMAIN`
- **macOS app**: `export BACKEND_URL=https://YOUR_DOMAIN` in your shell profile

## Security notes

- The backend has no authentication in v2 — anyone who knows the URL can POST photos and read the wine cache. For personal use this is acceptable; for shared/public deployments, put the API behind HTTP Basic Auth in nginx or add an API key check to FastAPI.
- The React curator is also unauthenticated. Restrict it to your own IP with `allow YOUR_IP; deny all;` inside the `location /` block if you don't want others curating your wine cache.
- The wine list photos you scan are sent to your server. They are not stored — only the extracted wine text and the downloaded bottle images are cached.
