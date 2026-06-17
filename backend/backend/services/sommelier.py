"""
SommelierService — per-wine Ollama calls for tasting notes + food pairings.
Stub for T1; full implementation in T5.

Runs in Phase 2 (after extraction stream closes) — Ollama is single-instance,
so sommelier calls are serial. Each call targets the same qwen3-vl:8b model
but uses a text-only prompt (no image), which is faster (~3-6s vs ~15-30s).

Graceful degrade: if the Ollama call fails, return NotesEvent with
tasting_note=None and pairings=[]. The wine is still shown to the user.
"""

from backend.models.wine import NotesEvent, WineObject


async def get_notes(wine: WineObject) -> NotesEvent:
    """
    Call Ollama for a 2-sentence tasting note and ≤3 food pairings.
    T5 implements the real httpx call. Gracefully degrade on failure.
    """
    # Stub: returns empty notes — replace in T5
    return NotesEvent(wine_id=wine.wine_id, tasting_note=None, pairings=[])
