# How-to: evaluate extraction quality

`backend/tests/eval_extraction.py` sends each photo in `resources/images/` to the backend's `/scan` endpoint, parses the SSE stream, and asserts corpus-level extraction quality. Run it after changing the prompt, switching models, or when extraction quality regresses.

## Prerequisites

- The backend running and reachable (default `http://localhost:8000` — see [backend/README.md](../../backend/README.md)).
- Ollama running with `qwen3-vl:8b` pulled, and the backend configured to reach it.
- A folder of wine list photos in `resources/images/` — not checked into the repo (see [resources/README.md](../../resources/README.md)); populate it with 10–20 photos spanning different list styles.

## Run the eval

It's an `integration`-marked pytest, so it's skipped by the default test run and only executes when you ask for it:

```bash
cd backend
uv sync --extra dev
BACKEND_URL=http://localhost:8000 uv run pytest -m integration tests/eval_extraction.py -v -s
```

`-s` prints the per-photo and aggregate report (otherwise pytest captures stdout). Set `BACKEND_URL` if your backend isn't on `localhost:8000`.

## Reading the report

For each photo the report prints wine count, SSE error-event count, and duration. The aggregate at the end shows:

- **Total wines extracted** across the corpus.
- **Avg confidence** — mean of the model's self-reported confidence per wine.
- **Low-confidence (<0.7)** — wines the model itself flagged as uncertain.
- **Error rate** — SSE `error` events as a fraction of wines extracted.

## The quality gate

The test passes only when all of these hold (thresholds defined at the top of `eval_extraction.py`):

- At least one wine extracted overall, and **≥ 1 wine per photo** (a photo yielding zero wines fails the run).
- **Avg confidence ≥ 0.70** (`MIN_AVG_CONFIDENCE`).
- **SSE error-event rate ≤ 5%** (`MAX_ERROR_EVENT_RATE`).

A failure tells you which assertion tripped: zero-wine photos and high error rates usually mean the model is adding commentary outside JSON or the photo is too hard (lighting/angle); low average confidence means genuinely marginal reads.

## Iterating on the prompt

The extraction prompt lives in `backend/backend/prompts/wine_extraction.py`. After editing it, restart the backend and re-run the eval against the same photo set to compare. The eval doesn't persist history, so note the prior run's numbers if you want a before/after.

> `Scripts/eval-extraction.swift` is a standalone pre-backend-split mirror (it embeds its own copy of the prompt and calls Ollama directly). The Python eval above is the canonical one — it exercises the real backend `/scan` path.
