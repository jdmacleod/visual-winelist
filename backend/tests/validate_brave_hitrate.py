"""
Integration test: Brave Image Search portrait-filter hit-rate validation.

Tests 20 wines spanning common, regional, and obscure bottles against the
Brave Image Search API and asserts that ≥70% return a portrait-ratio bottle
image. Mirrors Scripts/validate-brave-hitrate.swift, ported to Python.

Run with:
    cd backend
    uv sync --extra dev
    BRAVE_API_KEY=your_key pytest -m integration tests/validate_brave_hitrate.py -v -s

Requires:
    - BRAVE_API_KEY environment variable (Brave Search API key)
    - Network access to api.search.brave.com
"""

import os
import time

import httpx
import pytest

BRAVE_API_KEY = os.environ.get("BRAVE_API_KEY", "")
BRAVE_SEARCH_URL = "https://api.search.brave.com/res/v1/images/search"
PORTRAIT_RATIO = 1.2
PORTRAIT_TARGET = 0.70
RATE_LIMIT_DELAY = 1.1  # Brave Free plan: 1 request/second

TEST_WINES: list[tuple[str, str, str]] = [
    # tier: flagship / regional / obscure
    ("Château Margaux", "2018", "flagship"),
    ("Opus One", "2019", "flagship"),
    ("Penfolds Grange", "2018", "flagship"),
    ("Screaming Eagle", "2019", "flagship"),
    ("Domaine de la Romanée-Conti", "2017", "flagship"),
    ("Trimbach Riesling Clos Sainte Hune", "2018", "regional"),
    ("Donnhoff Oberhauser Brücke Auslese", "2020", "regional"),
    ("Alión", "2018", "regional"),
    ("Alvaro Palacios L'Ermita", "2019", "regional"),
    ("Cos d'Estournel", "2017", "regional"),
    ("Ridge Monte Bello", "2019", "regional"),
    ("Au Bon Climat Pinot Noir", "2020", "regional"),
    ("Domaine Weinbach Cuvée Théo", "2019", "obscure"),
    ("Clos Rougeard Saumur-Champigny", "2018", "obscure"),
    ("Movia Lunar", "2020", "obscure"),
    ("Radikon Ribolla Gialla", "2015", "obscure"),
    ("Gravner Anfora Bianco Breg", "2011", "obscure"),
    ("Elisabetta Foradori Granato", "2018", "obscure"),
    ("Weingut Keller G-Max Riesling", "2019", "obscure"),
    ("Sine Qua Non Poker Face", "2016", "obscure"),
]


@pytest.fixture(scope="module")
def api_key() -> str:
    if not BRAVE_API_KEY:
        pytest.skip("BRAVE_API_KEY not set — required for Brave hit-rate validation")
    return BRAVE_API_KEY


def _portrait_found(brave_results: list[dict[str, object]]) -> bool:
    """Return True if any result has h/w ratio > PORTRAIT_RATIO."""
    for result in brave_results:
        props = result.get("properties", {})
        if not isinstance(props, dict):
            continue
        h = props.get("height")
        w = props.get("width")
        if isinstance(h, int) and isinstance(w, int) and w > 0:
            if h / w > PORTRAIT_RATIO:
                return True
    return False


@pytest.mark.integration
def test_brave_portrait_hit_rate(api_key: str) -> None:
    """
    Query all 20 test wines via Brave Image Search and assert that ≥70%
    have a portrait-ratio bottle image. Prints a per-tier breakdown.
    """
    results: list[dict[str, object]] = []

    with httpx.Client(timeout=15) as client:
        for idx, (name, vintage, tier) in enumerate(TEST_WINES):
            if idx > 0:
                time.sleep(RATE_LIMIT_DELAY)

            query = f"{name} {vintage} wine bottle"
            response = client.get(
                BRAVE_SEARCH_URL,
                params={"q": query, "count": "5", "search_lang": "en"},
                headers={
                    "X-Subscription-Token": api_key,
                    "Accept": "application/json",
                },
            )

            portrait = False
            http_ok = response.status_code == 200
            if http_ok:
                brave_results: list[dict[str, object]] = response.json().get("results", [])
                portrait = _portrait_found(brave_results)

            results.append(
                {
                    "name": name,
                    "tier": tier,
                    "portrait": portrait,
                    "status": response.status_code,
                }
            )
            marker = "✓" if portrait else "✗"
            print(f"  [{idx + 1:>2}/{len(TEST_WINES)}] {marker} {name} ({vintage})")

    # Report
    total = len(results)
    portrait_count = sum(1 for r in results if r["portrait"])
    rate = portrait_count / total

    print(f"\n{'=' * 60}")
    print(f"BRAVE HIT RATE: {portrait_count}/{total} ({rate:.0%})")
    for tier in ("flagship", "regional", "obscure"):
        tier_r = [r for r in results if r["tier"] == tier]
        tier_ok = sum(1 for r in tier_r if r["portrait"])
        print(f"  {tier:<10} {tier_ok}/{len(tier_r)}")
    print(f"TARGET: ≥{PORTRAIT_TARGET:.0%}")
    failures = [str(r["name"]) for r in results if not r["portrait"]]
    if failures:
        print(f"Misses : {', '.join(failures)}")
    print(f"{'=' * 60}")

    assert rate >= PORTRAIT_TARGET, (
        f"Portrait hit rate {rate:.0%} < target {PORTRAIT_TARGET:.0%}. Failures: {failures}"
    )
