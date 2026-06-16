# Contributing

## Setup

See [README.md](README.md#setup) for Ollama and Brave API key setup. You'll need both running locally to exercise the full app, but unit tests don't require either.

## Build, test, lint

```
swift build
swift test
swift format lint -r --configuration .swift-format Sources Tests Scripts
```

To auto-fix formatting issues:

```
swift format -i -r --configuration .swift-format Sources Tests Scripts
```

CI (`.github/workflows/ci.yml`) runs all three on every push and PR to `main`.

## Making changes

- Keep PRs focused — one logical change per PR.
- If you change `Sources/VisualWinelist/Ollama/WineExtractionPrompt.swift`, run `Scripts/eval-extraction.swift` against a representative set of photos in `resources/images/` (see [resources/README.md](resources/README.md)) and note the before/after metrics in your PR description.
- If you change ranking/filtering logic in `Sources/VisualWinelist/Brave/BraveSearchClient.swift`, run `Scripts/validate-brave-hitrate.swift` and note the hit-rate change.
- See [docs/explanation/](docs/explanation/) for the architecture and the reasoning behind existing design decisions before changing core flows (camera retry, Ollama streaming, Brave ranking).

## Reporting issues

Use the bug report or feature request issue templates. For extraction/image-quality bugs, include the wine list photo if possible — it's the fastest way to reproduce and diagnose.
