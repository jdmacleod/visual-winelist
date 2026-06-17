"""
Tests for CacheService (T4): lookup, write (upsert), delete, search, curate.
All tests use the per-test SQLite DB wired up by conftest.use_test_db.
"""

import json
from unittest.mock import AsyncMock, patch

from backend.models.wine import WineObject
from backend.services import cache
from tests.conftest import make_jpeg


def _wine(
    name: str = "Château Margaux",
    producer: str | None = "Château Margaux",
    vintage: str | None = "2018",
) -> WineObject:
    return WineObject(name=name, producer=producer, vintage=vintage, confidence=0.92)


# ---------------------------------------------------------------------------
# lookup
# ---------------------------------------------------------------------------


async def test_lookup_miss():
    result = await cache.lookup("nonexistent-wine-id")
    assert result is None


async def test_lookup_hit_after_write():
    wine = _wine()
    await cache.write(wine, "/images/margaux.jpg", None, [])

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.name == "Château Margaux"
    assert record.producer == "Château Margaux"
    assert record.vintage == "2018"
    assert record.image_path == "/images/margaux.jpg"
    assert record.tasting_note is None
    assert record.pairings == []
    assert record.verified is False


# ---------------------------------------------------------------------------
# write — upsert behaviour
# ---------------------------------------------------------------------------


async def test_write_creates_record():
    wine = _wine()
    await cache.write(wine, "/img/w.jpg", "Elegant finish", ["lamb", "duck"])

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.tasting_note == "Elegant finish"
    assert record.pairings == ["lamb", "duck"]


async def test_write_upserts_image_path_on_second_call():
    wine = _wine()
    await cache.write(wine, "/img/old.jpg", None, [])
    await cache.write(wine, "/img/new.jpg", None, [])

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path == "/img/new.jpg"


async def test_write_upserts_notes_without_overwriting_image():
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])
    await cache.write(wine, None, "Great tannins", ["beef"])

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path == "/img/bottle.jpg"  # preserved
    assert record.tasting_note == "Great tannins"  # updated
    assert record.pairings == ["beef"]  # updated


async def test_write_empty_pairings_does_not_clear_existing():
    wine = _wine()
    await cache.write(wine, None, None, ["cheese", "fruit"])
    await cache.write(wine, None, None, [])  # empty → should not clear

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.pairings == ["cheese", "fruit"]


async def test_write_none_tasting_note_does_not_clear_existing():
    wine = _wine()
    await cache.write(wine, None, "Complex bouquet", [])
    await cache.write(wine, None, None, [])  # None → should not clear

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.tasting_note == "Complex bouquet"


# ---------------------------------------------------------------------------
# delete
# ---------------------------------------------------------------------------


async def test_delete_existing_record():
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])

    deleted = await cache.delete(wine.wine_id)
    assert deleted is True
    assert await cache.lookup(wine.wine_id) is None


async def test_delete_nonexistent_returns_false():
    deleted = await cache.delete("no-such-wine")
    assert deleted is False


# ---------------------------------------------------------------------------
# GET /wines/search
# ---------------------------------------------------------------------------


async def test_search_empty_db(client):
    r = await client.get("/wines/search")
    assert r.status_code == 200
    body = r.json()
    assert body["results"] == []
    assert body["total"] == 0


async def test_search_returns_written_records(client):
    await cache.write(_wine("Opus One", "Opus One", "2019"), "/img/opus.jpg", None, [])
    await cache.write(_wine("Screaming Eagle", "Screaming Eagle", "2020"), "/img/se.jpg", None, [])

    r = await client.get("/wines/search")
    assert r.status_code == 200
    assert r.json()["total"] == 2


async def test_search_filters_by_name(client):
    await cache.write(_wine("Château Margaux", "Château Margaux", "2018"), "/img/m.jpg", None, [])
    await cache.write(_wine("Opus One", "Opus One", "2019"), "/img/o.jpg", None, [])

    r = await client.get("/wines/search", params={"q": "Margaux"})
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 1
    assert body["results"][0]["name"] == "Château Margaux"


async def test_search_result_includes_image_url(client):
    await cache.write(_wine(), "/img/bottle.jpg", "Notes here", ["lamb"])

    r = await client.get("/wines/search")
    result = r.json()["results"][0]
    assert result["image_url"] == f"/wines/{_wine().wine_id}/image"
    assert result["tasting_note"] == "Notes here"
    assert result["pairings"] == ["lamb"]


async def test_search_no_image_url_when_no_image(client):
    await cache.write(_wine(), None, None, [])

    r = await client.get("/wines/search")
    result = r.json()["results"][0]
    assert result["image_url"] is None


# ---------------------------------------------------------------------------
# POST /curate
# ---------------------------------------------------------------------------


async def test_curate_sets_verified(client):
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])

    r = await client.post("/curate", json={"wine_id": wine.wine_id, "verified": True})
    assert r.status_code == 200
    assert r.json()["verified"] is True

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.verified is True


async def test_curate_unverify(client):
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])
    await client.post("/curate", json={"wine_id": wine.wine_id, "verified": True})

    r = await client.post("/curate", json={"wine_id": wine.wine_id, "verified": False})
    assert r.status_code == 200
    assert r.json()["verified"] is False


async def test_curate_not_found(client):
    r = await client.post("/curate", json={"wine_id": "no-such-id"})
    assert r.status_code == 404


# ---------------------------------------------------------------------------
# GET /wines/{wine_id}/image
# ---------------------------------------------------------------------------


async def test_get_image_not_in_cache(client):
    r = await client.get("/wines/no-such-id/image")
    assert r.status_code == 404


async def test_get_image_in_cache_but_file_missing(client):
    wine = _wine()
    await cache.write(wine, "/nonexistent/path.jpg", None, [])

    r = await client.get(f"/wines/{wine.wine_id}/image")
    assert r.status_code == 404


async def test_get_image_serves_file(client, tmp_path):
    img = tmp_path / "bottle.jpg"
    img.write_bytes(b"fake-jpeg-content")
    wine = _wine()
    await cache.write(wine, str(img), None, [])

    r = await client.get(f"/wines/{wine.wine_id}/image")
    assert r.status_code == 200
    assert r.content == b"fake-jpeg-content"


# ---------------------------------------------------------------------------
# DELETE /wines/{wine_id}
# ---------------------------------------------------------------------------


async def test_delete_wine_endpoint(client):
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])

    r = await client.delete(f"/wines/{wine.wine_id}")
    assert r.status_code == 204
    assert await cache.lookup(wine.wine_id) is None


async def test_delete_wine_endpoint_not_found(client):
    r = await client.delete("/wines/no-such-id")
    assert r.status_code == 404


# ---------------------------------------------------------------------------
# Scan integration: cache hit skips Brave
# ---------------------------------------------------------------------------


async def test_scan_cache_hit_skips_brave(client):
    """
    If a wine is already cached with an image, the scan SSE stream should emit
    an image event immediately from cache and brave_client.fetch_image must not
    be called for that wine.
    """
    wine = _wine()
    await cache.write(wine, "/img/cached.jpg", None, [])

    _WINE_JSON = json.dumps(
        {
            "name": wine.name,
            "producer": wine.producer,
            "vintage": wine.vintage,
            "variety": None,
            "appellation": None,
            "price": None,
            "description": None,
            "listSection": None,
            "rawText": None,
            "confidence": 0.92,
        }
    )

    async def _fake_extract(image_data: bytes):  # type: ignore[override]

        yield WineObject.model_validate_json(_WINE_JSON)

    with (
        patch("backend.services.ollama_client.extract_wines", side_effect=_fake_extract),
        patch(
            "backend.services.brave_client.fetch_image",
            new=AsyncMock(return_value=None),
        ) as mock_brave,
    ):
        r = await client.post(
            "/scan",
            files={"image": ("w.jpg", make_jpeg(), "image/jpeg")},
        )

    assert r.status_code == 200
    mock_brave.assert_not_called()

    events = [line[len("event: ") :] for line in r.text.splitlines() if line.startswith("event: ")]
    assert "image" in events
    # The image event comes from cache (placeholder=False)
    image_data_lines = [
        line[len("data: ") :]
        for line in r.text.splitlines()
        if line.startswith("data: ") and "placeholder" in line
    ]
    assert image_data_lines
    first_image = json.loads(image_data_lines[0])
    assert first_image.get("placeholder") is False
