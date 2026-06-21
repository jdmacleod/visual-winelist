import hashlib
from typing import Any

from pydantic import BaseModel, field_validator


def _cache_key(producer: str | None, name: str, vintage: str | None) -> str:
    # D11: normalize empty/None producer to name
    p = (producer or "").strip().lower() or name.lower()
    n = name.lower()
    v = (vintage or "nv").lower()
    raw = f"{p}:{n}:{v}"
    return hashlib.sha256(raw.encode()).hexdigest()


class WineObject(BaseModel):
    """Mirrors WineObject.swift — 10 extraction fields + computed wine_id."""

    name: str
    producer: str | None = None
    vintage: str | None = None
    variety: str | None = None
    appellation: str | None = None
    price: str | None = None
    description: str | None = None
    listSection: str | None = None
    rawText: str | None = None
    confidence: float

    @property
    def wine_id(self) -> str:
        return _cache_key(self.producer, self.name, self.vintage)

    def model_dump_with_id(self) -> dict[str, Any]:
        d = self.model_dump()
        d["wine_id"] = self.wine_id
        return d


# SSE event payloads


class ImageEvent(BaseModel):
    wine_id: str
    url: str  # /wines/{wine_id}/image — client fetches bytes separately (D10)
    placeholder: bool = False


class NotesEvent(BaseModel):
    wine_id: str
    tasting_note: str | None = None
    pairings: list[str] = []


class ErrorEvent(BaseModel):
    code: str
    wine_index: int | None = None
    message: str


class CompleteEvent(BaseModel):
    wine_count: int
    cache_hits: int
    scan_id: str
    ollama_ms: int | None = None
    image_ms: int | None = None
    sommelier_ms: int | None = None
    total_ms: int | None = None


# Curator / search response models


class WineRecord(BaseModel):
    wine_id: str
    name: str
    producer: str | None = None
    vintage: str | None = None
    variety: str | None = None
    appellation: str | None = None
    tasting_note: str | None = None
    pairings: list[str] = []
    verified: bool = False
    image_url: str | None = None

    model_config = {"from_attributes": True}


class CurateRequest(BaseModel):
    wine_id: str
    image_url: str | None = None
    verified: bool = True


class WinePatch(BaseModel):
    """Partial update payload for curator edits. Only provided fields are written."""

    name: str | None = None
    producer: str | None = None
    vintage: str | None = None
    variety: str | None = None
    appellation: str | None = None

    @field_validator("name", "producer", "vintage", "variety", "appellation", mode="before")
    @classmethod
    def reject_blank(cls, v: object) -> object:
        if isinstance(v, str) and not v.strip():
            raise ValueError("must not be blank")
        return v


class SearchResponse(BaseModel):
    results: list[WineRecord]
    total: int
    page: int
    page_size: int
    verified_total: int = 0
