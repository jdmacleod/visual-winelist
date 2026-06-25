# Reference: configuration

Extraction, image search, and caching are configured on the **backend**; the iOS app only needs to know where the backend lives. [backend/README.md](../../backend/README.md) is the authoritative configuration reference — the table below mirrors it for convenience.

## Backend environment variables

Set these where the backend runs (a `.env` file in `backend/`, or the process environment):

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `BRAVE_API_KEY` | yes | — | Brave Search API key for bottle-image lookup. |
| `OLLAMA_BASE_URL` | no | `http://localhost:11434` | Ollama server URL (extraction + sommelier). |
| `OLLAMA_MODEL` | no | `qwen3-vl:8b` | Vision model used for extraction. Must be pulled (`ollama pull qwen3-vl:8b`). |
| `IMAGE_CACHE_DIR` | no | `./image-cache` | Directory for cached bottle images. |
| `MAX_UPLOAD_SIZE` | no | `26214400` (25 MB) | Max accepted photo upload, in bytes. |
| `TELEMETRY_ENABLED` | no | `true` | Accept opt-in scan diagnostics at `POST /telemetry/scan` (the iOS "Send Diagnostics?" toggle). |
| `SAVE_SCAN_IMAGES` | no | `false` | Persist each uploaded photo to `image-cache/scans/{scan_id}.jpg` for inspection. |
| `SCAN_IMAGE_RETENTION_DEFAULT` | no | `50` | When scan-image saving is on and no per-request retention is sent, keep at most this many newest photos (0 disables pruning). |

Extraction and image-search tunables (Ollama timeout/temperature, Brave result count, ranking, retry behavior) live in the backend services — `backend/backend/services/ollama_client.py` and `backend/backend/services/brave_client.py` — and are described in [the architecture explanation](../explanation/architecture.md).

## iOS app configuration

The app has no compile-time configuration. Runtime settings:

| Setting | Where | Notes |
|---|---|---|
| Backend URL | First-launch setup screen, or **Settings → Visual Winelist → Backend URL**, or in-app Preferences | `http://<backend-LAN-IP>:8000`; both devices must share a Wi-Fi network. |
| Show price on card | In-app Preferences (gear icon) | Persisted via `@AppStorage`; toggles the price badge on each grid card. |
| Send Diagnostics? | In-app Preferences / iOS Settings | Off by default; posts per-scan timing only (no photo or wine data) to `POST /telemetry/scan`. |

## Required permissions (iOS)

Declared in `ios/Sources/VisualWinelistIOS/Info.plist`:

- `NSCameraUsageDescription` — for capturing wine list photos.
- `NSMicrophoneUsageDescription` — required by AVFoundation when accessing the camera.
