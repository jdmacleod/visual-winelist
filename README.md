# Visual Winelist

[![CI](https://github.com/jdmacleod/visual-winelist/actions/workflows/ci.yml/badge.svg)](https://github.com/jdmacleod/visual-winelist/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/jdmacleod/visual-winelist)](https://github.com/jdmacleod/visual-winelist/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://github.com/jdmacleod/visual-winelist)
[![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)

A macOS app that turns a photo of a restaurant wine list into a visual grid of tappable bottle images.

Point your Mac's camera at a printed or handwritten wine list, tap to capture, and Visual Winelist extracts every wine it can read — name, vintage, grape, region, price — then looks up a bottle photo for each one. Tap any bottle to see full details.

Wine list text never leaves your Mac: extraction runs against a local [Ollama](https://ollama.com) model (Qwen3-VL). Only the extracted wine name/producer/vintage is sent to Brave Search to find a bottle photo.

This is a v0.1.0 proof of concept — see [CHANGELOG.md](CHANGELOG.md) for release notes.

## Requirements

- macOS 14+
- [Ollama](https://ollama.com) running locally with the `qwen3-vl:8b` model pulled:
  ```
  ollama pull qwen3-vl:8b
  ollama serve
  ```
- A free [Brave Search API](https://brave.com/search/api/) key for bottle image lookup

## Setup

1. Get a Brave Search API key and export it in your shell profile:
   ```
   export BRAVE_API_KEY=your_key_here
   ```
2. Make sure Ollama is running (`ollama serve`) with `qwen3-vl:8b` pulled.
3. Build and run:
   ```
   swift build
   swift run
   ```
   Or open `Package.swift` in Xcode and run the `VisualWinelist` scheme.

If `BRAVE_API_KEY` isn't set, the app shows a setup screen with instructions instead of crashing.

## Usage

1. Grant camera access when prompted.
2. Point the camera at a wine list and tap anywhere to capture.
3. Wait while Ollama reads the photo — extracted wines populate a grid as they're found, with bottle photos arriving shortly after each one.
4. Tap a bottle for full details, including an extraction-debug panel (raw OCR text, confidence, parsed fields, the exact Brave query used).
5. Use **Scan more** to photograph additional pages of a multi-page list (new wines are appended, duplicates by name+vintage are skipped). Use **Clear** to empty the grid and start over.

## Architecture

```
Camera (AVFoundation) → Ollama (Qwen3-VL, streaming JSONL) → WineListViewModel → Brave Image Search → SwiftUI grid/detail views
```

- **Camera/** — `CameraManager` wraps `AVCaptureSession`, retries transient capture glitches caused by Continuity Camera video effects, and exposes a SwiftUI preview layer.
- **Ollama/** — `OllamaClient` streams a wine list photo to a local Qwen3-VL model and parses one `WineObject` per JSON line as it arrives. `WineExtractionPrompt` is the prompt under iteration.
- **Brave/** — `BraveSearchClient` queries Brave Image Search per wine and downloads the best-ranked bottle photo, rate-limited to the Free plan's 1 req/sec.
- **Cache/** — `ImageCache` persists downloaded bottle photos to `~/.visual-winelist/image-cache/`, keyed by a SHA256 hash of name+vintage, so repeat scans skip the network.
- **ViewModels/** — `WineListViewModel` orchestrates extraction + image fetch and owns the grid's state.
- **Views/** — `ContentView` drives the camera → scanning → grid phase flow; `WineGridView`/`WineBottleCard`/`WineDetailView` render the results.

See [docs/explanation/architecture.md](docs/explanation/architecture.md) for the full data-flow walkthrough and the design decisions behind it.

## Documentation

- [Tutorial: scan your first wine list](docs/tutorial/first-scan.md)
- [How-to: evaluate extraction quality](docs/how-to/evaluate-extraction.md)
- [How-to: validate Brave image search hit rate](docs/how-to/validate-brave-hitrate.md)
- [Reference: wine extraction JSON schema](docs/reference/wine-schema.md)
- [Reference: configuration](docs/reference/configuration.md)
- [Explanation: architecture & data flow](docs/explanation/architecture.md)
- [Explanation: design decisions](docs/explanation/design-decisions.md)

## Development

```
swift build        # build
swift test          # run unit tests
swift Scripts/eval-extraction.swift                       # eval the extraction prompt against resources/images/
BRAVE_API_KEY=... swift Scripts/validate-brave-hitrate.swift  # eval Brave image hit rate
```

See [resources/README.md](resources/README.md) for populating eval images.
