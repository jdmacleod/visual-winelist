"""
Integration test: extraction quality eval against resources/images/.

Sends each photo in resources/images/ to the backend's /scan endpoint,
parses the SSE stream, and asserts quality metrics across the corpus.
Mirrors the logic of Scripts/eval-extraction.swift but tests the full
backend API surface rather than calling Ollama directly.

Run with:
    cd backend
    uv sync --extra dev
    BACKEND_URL=http://localhost:8000 pytest -m integration tests/eval_extraction.py -v -s

Requires:
    - Backend running at BACKEND_URL (default http://localhost:8000)
    - Ollama running with qwen3-vl:8b and the backend configured to reach it
    - At least one image in resources/images/ (see resources/README.md)
"""

import json
import os
import time
from pathlib import Path

import httpx
import pytest

BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8000")
RESOURCES_DIR = Path(__file__).parent.parent.parent / "resources" / "images"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}

MIN_AVG_CONFIDENCE = 0.70
MAX_ERROR_EVENT_RATE = 0.05
MIN_WINES_PER_PHOTO = 1


def _parse_sse_events(text: str) -> list[dict[str, object]]:
    """Parse an SSE response body into a list of {event, data} dicts."""
    events: list[dict[str, object]] = []
    current_event: str | None = None
    current_data: list[str] = []

    for line in text.splitlines():
        if line.startswith("event: "):
            current_event = line[7:].strip()
        elif line.startswith("data: "):
            current_data.append(line[6:].strip())
        elif line == "" and current_event and current_data:
            try:
                parsed = json.loads(" ".join(current_data))
                events.append({"event": current_event, "data": parsed})
            except json.JSONDecodeError:
                pass
            current_event = None
            current_data = []

    return events


@pytest.fixture(scope="module")
def image_paths() -> list[Path]:
    if not RESOURCES_DIR.exists():
        pytest.skip(f"resources/images/ not found at {RESOURCES_DIR}")
    paths = sorted(p for p in RESOURCES_DIR.iterdir() if p.suffix.lower() in IMAGE_EXTENSIONS)
    if not paths:
        pytest.skip("No images found in resources/images/ — see resources/README.md")
    return paths


@pytest.mark.integration
def test_backend_reachable_for_eval() -> None:
    """Fail fast with a clear message if the backend is not running."""
    try:
        resp = httpx.get(f"{BACKEND_URL}/health", timeout=5)
        assert resp.status_code == 200, f"Health check returned {resp.status_code}"
    except httpx.ConnectError:
        pytest.fail(
            f"Backend not reachable at {BACKEND_URL}. "
            "Start it with: cd backend && uvicorn backend.main:app --reload"
        )


@pytest.mark.integration
def test_extraction_quality(image_paths: list[Path]) -> None:
    """
    End-to-end extraction quality eval: POST each image to /scan, parse SSE
    stream, and assert corpus-level quality metrics.

    Per-photo and aggregate metrics are printed to stdout (use -s to see them).
    """
    all_wines: list[dict[str, object]] = []
    error_event_count = 0
    per_photo: list[dict[str, object]] = []

    for img_path in image_paths:
        start = time.perf_counter()
        img_bytes = img_path.read_bytes()

        with httpx.stream(
            "POST",
            f"{BACKEND_URL}/scan",
            files={"photo": (img_path.name, img_bytes, "image/jpeg")},
            timeout=300,
        ) as response:
            assert response.status_code == 200, (
                f"{img_path.name}: /scan returned HTTP {response.status_code}"
            )
            body = response.read().decode("utf-8")

        duration = time.perf_counter() - start
        events = _parse_sse_events(body)

        wines = [e["data"] for e in events if e["event"] == "wine"]
        errors = [e["data"] for e in events if e["event"] == "error"]

        all_wines.extend(wines)  # type: ignore[arg-type]
        error_event_count += len(errors)

        per_photo.append(
            {
                "filename": img_path.name,
                "wine_count": len(wines),
                "error_count": len(errors),
                "duration": duration,
            }
        )

    # Print report
    confidences = [
        float(w["confidence"])  # type: ignore[arg-type]
        for w in all_wines
        if "confidence" in w  # type: ignore[operator]
    ]
    avg_conf = sum(confidences) / len(confidences) if confidences else 0.0
    low_conf = sum(1 for c in confidences if c < 0.7)
    error_rate = error_event_count / max(len(all_wines), 1)

    print(f"\n{'=' * 72}")
    print(f"EXTRACTION EVAL — {len(image_paths)} photo(s)  backend={BACKEND_URL}")
    print(f"{'=' * 72}")
    for r in per_photo:
        print(
            f"  {str(r['filename']):<42} {r['wine_count']:>3} wines  "
            f"{r['error_count']} errors  {r['duration']:.1f}s"
        )
    print(f"\nTotal wines extracted : {len(all_wines)}")
    print(f"Avg confidence        : {avg_conf:.2f}")
    print(f"Low-confidence (<0.7) : {low_conf}/{len(all_wines)}")
    print(f"SSE error events      : {error_event_count}")
    print(f"Error rate            : {error_rate:.2%}")
    print(f"{'=' * 72}")

    # Assertions
    assert len(all_wines) > 0, "No wines extracted from any image"
    assert avg_conf >= MIN_AVG_CONFIDENCE, (
        f"Avg confidence {avg_conf:.2f} below threshold {MIN_AVG_CONFIDENCE}"
    )
    assert error_rate <= MAX_ERROR_EVENT_RATE, (
        f"SSE error event rate {error_rate:.2%} exceeds threshold {MAX_ERROR_EVENT_RATE:.2%}"
    )
    for r in per_photo:
        assert int(str(r["wine_count"])) >= MIN_WINES_PER_PHOTO, (
            f"{r['filename']}: extracted 0 wines (expected ≥ {MIN_WINES_PER_PHOTO})"
        )
