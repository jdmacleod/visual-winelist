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

## Required entitlements / permissions

Declared in `VisualWinelist.entitlements` and `Sources/VisualWinelist/Resources/Info.plist`:

- Camera access (`com.apple.security.device.camera`, `NSCameraUsageDescription`) — for capturing wine list photos
- Network client (`com.apple.security.network.client`) — for Brave Search API and local Ollama
- Read/write access to `~/.visual-winelist/` (`com.apple.security.temporary-exception.files.home-relative-path.read-write`) — for the image cache
