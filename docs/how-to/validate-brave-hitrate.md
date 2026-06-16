# How-to: validate Brave image search hit rate

`Scripts/validate-brave-hitrate.swift` queries Brave Image Search for 20 known wines (flagship, regional, and obscure tiers) and reports how often a usable bottle photo comes back. Run it before relying on Brave as the bottle-image source, or after changing the query format or ranking logic in `BraveSearchClient`.

## Run it

```
BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift
```

Add `--verbose` to print response bodies for failures and thumbnail URLs for successes:

```
BRAVE_API_KEY=your_key swift Scripts/validate-brave-hitrate.swift --verbose
```

The script runs sequentially with a 1.1s gap between queries to respect Brave's Free plan rate limit (1 req/sec).

## Reading the report

Results are grouped by tier (flagship/regional/obscure) with a per-wine line showing either the passing aspect-ratio results or the specific failure reason: network error, HTTP error, JSON decode failure, zero results, missing dimension data, or every result failing the portrait filter.

The totals section reports three percentages:

- **Portrait bottle image found** — the primary metric; percentage of queries where at least one result has a portrait aspect ratio (h/w > 1.2)
- **Results with dimension data** — percentage where Brave returned width/height at all
- **Any result returned** — percentage where Brave found anything

Target is ≥70% portrait hit rate for v1 viability. If portrait rate is low but dimension-data rate is high, the filter threshold may be too strict. If dimension data itself is sparse, check the Brave API tier/params. If even raw results are sparse, Brave coverage may be insufficient and a fallback image source should be considered.

Note: this script tests the simple `count=5` + hard portrait filter from before the production fixes in `BraveSearchClient.swift` (which raised `count` to 20, replaced the hard filter with a ranked score, and added a `User-Agent` header). Use it as a rough signal on tier-by-tier Brave coverage rather than an exact mirror of the app's current behavior — see [Explanation: design decisions](../explanation/design-decisions.md) for what changed and why.
