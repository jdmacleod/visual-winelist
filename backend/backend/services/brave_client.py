"""
BraveSearchClient — image search + portrait ranking + token-bucket rate limiter.
Stub for T1; full implementation in T3.

Implementation notes for T3:
- User-Agent: Mozilla/5.0 (required by Brave CDN — requests without it get 403)
- Rate limiter: 1 req/sec token bucket (matches Brave Free plan limit)
- Portrait ranking: prefer images with h/w ratio > 1.2
- 20 results requested, try top 8 candidates
- Content-Length pre-check (D3): check header BEFORE reading body;
  skip candidate if Content-Length > 2MB; stream-abort at 2MB if no header
"""

from backend.models.wine import ImageEvent, WineObject


async def fetch_image(wine: WineObject) -> ImageEvent | None:
    """
    Search Brave for a bottle image; cache result; return ImageEvent.
    T3 implements the full search + download + cache write path.
    """
    # Stub: returns None (no image) — replace in T3
    return None


async def check_ollama_reachable(base_url: str) -> bool:
    """Probe Ollama /api/tags for health check."""
    # Stub — replace in T2/T3 with real httpx probe
    return False
