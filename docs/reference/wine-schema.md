# Reference: wine extraction JSON schema

The backend asks Qwen3-VL to emit one JSON object per line (JSONL), each matching this schema. The canonical definition is [`shared/wine-schema.json`](../../shared/wine-schema.json); `backend/tests/test_schema_sync.py` keeps it in sync with the backend model (`backend/backend/models/wine.py`), the iOS `WineObject` (`ios/Sources/VisualWinelistIOS/Models/WineObject.swift`), and the web type (`web/src/types/wine.ts`). The extraction prompt that requests this shape lives in `backend/backend/prompts/wine_extraction.py`.

These are the 10 **extraction-phase** fields the model produces. `wine_id`, the tasting note, and pairings are added later by the backend (Phase 2 SSE events), not extracted from the photo.

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

The backend assigns each wine a `wine_id`. On iOS, `WineObject.id` is `wineId ?? "\(name.lowercased())-\(vintage ?? "nv")"` — it uses the server id when present and otherwise falls back to a name+vintage key. Equality (`==`) compares `name` and `vintage` case-insensitively, so two wines are the same if both match regardless of other fields. `WineListViewModel.appendScan` uses this to skip duplicates when scanning additional pages of the same list.

## Confidence

iOS `WineState.isLowConfidence` is `true` when `confidence < 0.7`. The grid shows a small "?" badge on low-confidence bottles, and the detail view shows an explicit warning. The extraction prompt instructs the model to use 0.9+ for clear text, 0.6–0.8 for partially legible text, and below 0.6 for guesses — confidence reflects the model's own uncertainty, not a downstream calibration.

## Streaming parse behavior

`backend/backend/services/ollama_client.py`'s `extract_wines` reads the Ollama `/api/chat` streaming response, accumulates a token buffer (continuing the assistant pre-fill `"{"`), and attempts to parse a `WineObject` each time it sees a complete line starting with `{`. Lines that fail to parse are skipped — only lines starting with `{` are attempted, so model commentary outside JSON generates no parse noise. Each parsed wine is forwarded to the client as an `event: wine` immediately. See [the architecture explanation](../explanation/architecture.md) for how parsed wines flow through the SSE stream.
