# How-to: evaluate extraction quality

`Scripts/eval-extraction.swift` runs the current `WineExtractionPrompt` against a folder of real wine list photos and reports aggregate quality metrics. Use it after changing the prompt, switching models, or when extraction quality regresses.

## Prerequisites

- Ollama running locally with `qwen3-vl:8b` pulled (`ollama serve`)
- A folder of wine list photos in `resources/images/` — not checked into the repo (see [resources/README.md](../../resources/README.md)); populate it yourself with 10–20 photos spanning different list styles

## Run the eval

```
swift Scripts/eval-extraction.swift
```

Add `--verbose` to print every extracted wine and any JSON parse errors per photo:

```
swift Scripts/eval-extraction.swift --verbose
```

## Reading the report

For each photo, the script prints wine count, low-confidence count, parse error count, and duration. The summary at the end aggregates across all photos:

- **Avg confidence** — mean of the model's self-reported confidence per wine
- **Low-confidence (<0.7)** — wines the model itself flagged as uncertain
- **Section header / vintage / price captured** — coverage of optional fields, which indicates how much structured detail the prompt is pulling out beyond just the wine name

The script ends with a verdict:

- **PASS** — zero parse errors, avg confidence ≥0.8, zero low-confidence wines. Prompt is production-ready.
- **MARGINAL** — avg confidence ≥0.7 and parse error rate under 5%. Usable, but review low-confidence wines with `--verbose` before relying on it.
- **FAIL** — iterate on `Sources/VisualWinelist/Ollama/WineExtractionPrompt.swift` before shipping. The script tells you whether the issue is parse errors (model adding commentary outside JSON) or low confidence (genuinely hard photos — check lighting/angle).

## Iterating on the prompt

The prompt lives in `Sources/VisualWinelist/Ollama/WineExtractionPrompt.swift`. After editing it, re-run the eval against the same photo set to compare results — the script doesn't persist history, so keep a note of the prior run's numbers if you want a before/after comparison.
