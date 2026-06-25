# Reference: configuration

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `BRAVE_API_KEY` | yes | — | Brave Search API key used for bottle image lookup. Checked at app launch by `StartupValidator`; if missing or empty, the app shows a "Setup Required" screen instead of the camera. |

## Hardcoded settings

These aren't currently exposed as configuration but are the values you'd change to retune behavior:

| Setting | Location | Value | Notes |
|---|---|---|---|
| Ollama base URL | `OllamaClient.init` | `http://localhost:11434` | Local Ollama server |
| Ollama model | `OllamaClient.init` | `qwen3-vl:8b` | Must be pulled locally (`ollama pull qwen3-vl:8b`) |
| Ollama request timeout | `OllamaClient.startStream` | 120s | Covers the full streaming extraction |
| Ollama temperature | `OllamaClient.startStream` | 0.1 | Low temperature for consistent JSON output |
| Brave search count | `BraveSearchClient.fetchBottleImage` | 20 | Results requested per wine |
| Brave candidates tried | `BraveSearchClient.fetchBottleImage` | 8 | Top-ranked candidates attempted for download before giving up |
| Brave rate limit | `BraveSearchClient`'s `RateLimiter` | 1 req/sec | Matches Brave Free plan |
| Brave request timeout | `BraveSearchClient.fetchBottleImage` | 10s | Search request |
| Brave download timeout | `BraveSearchClient.downloadImage` | 8s | Per-candidate image download |
| Camera capture retries | `CameraManager.capturePhoto` | 3 attempts, 250ms apart | Works around Continuity Camera "Reactions" frame corruption |
| Image cache location | `ImageCache.init` | `~/.visual-winelist/image-cache/` | Keyed by SHA256(name+vintage), `.jpg` files |
| Low-confidence threshold | `WineState.isLowConfidence` | `< 0.7` | Drives the "?" badge and detail-view warning |

## Required permissions (iOS)

Declared in `ios/Sources/VisualWinelistIOS/Info.plist`:

- `NSCameraUsageDescription` — for capturing wine list photos
- `NSMicrophoneUsageDescription` — required by AVFoundation when accessing the camera

> Note: the rows above this section describe the original monolithic Swift client. Image extraction (Ollama), image search (Brave), and the image cache now live in the FastAPI backend — see [backend/README.md](../../backend/README.md) for their current configuration.
