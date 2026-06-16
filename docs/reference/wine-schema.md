# Reference: wine extraction JSON schema

`OllamaClient` asks Qwen3-VL to emit one JSON object per line (JSONL), each matching this schema. The prompt text lives in `Sources/VisualWinelist/Ollama/WineExtractionPrompt.swift`; the Swift decoding type is `WineObject` in `Sources/VisualWinelist/Models/WineObject.swift`.

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | yes | Wine name as printed on the list |
| `producer` | string \| null | no | Winery/producer; often identical to `name` |
| `vintage` | string \| null | no | 4-digit year as a string, e.g. `"2019"` |
| `variety` | string \| null | no | Grape variety or blend, e.g. `"Cabernet Sauvignon"` |
| `appellation` | string \| null | no | Region/appellation, e.g. `"Napa Valley, California"` |
| `price` | string \| null | no | Price as printed, including currency symbol |
| `description` | string \| null | no | Tasting notes or description text from the list |
| `listSection` | string \| null | no | Section header the wine appears under, e.g. `"Red Wines"` |
| `rawText` | string \| null | no | Complete original text for this entry |
| `confidence` | number | yes | 0.0–1.0 self-reported certainty in `name`/`vintage` extraction |

## Identity and deduplication

`WineObject.id` is `"\(name.lowercased())-\(vintage ?? "nv")"`. Equality (`==`) compares `name` and `vintage` case-insensitively — two wines are considered the same if both match, regardless of any other field. `WineListViewModel.appendScan` uses this to skip duplicates when scanning additional pages of the same list.

## Confidence

`WineState.isLowConfidence` is `true` when `confidence < 0.7`. The grid shows a small "?" badge on low-confidence bottles, and the detail view shows an explicit warning banner. The extraction prompt instructs the model to use 0.9+ for clear text, 0.6–0.8 for partially legible text, and below 0.6 for guesses — confidence reflects the model's own uncertainty, not a downstream calibration.

## Streaming parse behavior

`OllamaClient.extractWines` reads the Ollama `/api/chat` streaming response byte-by-byte, accumulates a token buffer, and attempts to parse a `WineObject` every time it sees a complete line starting with `{` (newline-delimited) or a buffer that already looks like a complete `{...}` object (in case the model omits a trailing newline). Lines that fail to parse are silently skipped — only lines starting with `{` are attempted at all, so model commentary outside JSON doesn't generate parse noise. If zero wines parse from a non-empty response, `extractWines` throws `OllamaError.noWinesFound`.
