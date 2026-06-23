"""
Tests for CacheService (T4): lookup, write (upsert), delete, search, curate.
All tests use the per-test SQLite DB wired up by conftest.use_test_db.
"""

import hashlib
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
    image_url = result["image_url"]
    assert image_url.startswith(f"/wines/{_wine().wine_id}/image?v=")
    ts = image_url.split("?v=")[1]
    assert ts.isdigit() and int(ts) > 0, f"Expected a positive integer timestamp, got: {ts!r}"
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


# ---------------------------------------------------------------------------
# cache.update_image()
# ---------------------------------------------------------------------------


async def test_update_image_happy_path():
    wine = _wine()
    await cache.write(wine, "/old/path.jpg", None, [])
    result = await cache.update_image(wine.wine_id, "/new/path.jpg")
    assert result is True
    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path == "/new/path.jpg"


async def test_update_image_not_found():
    result = await cache.update_image("no-such-id", "/some/path.jpg")
    assert result is False


# ---------------------------------------------------------------------------
# cache.update_image_and_verify()
# ---------------------------------------------------------------------------


async def test_update_image_and_verify_happy_path():
    wine = _wine()
    await cache.write(wine, "/old/path.jpg", None, [])
    result = await cache.update_image_and_verify(wine.wine_id, "/new/path.jpg")
    assert result is True
    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path == "/new/path.jpg"
    assert record.verified is True


async def test_update_image_and_verify_not_found():
    result = await cache.update_image_and_verify("no-such-id", "/some/path.jpg")
    assert result is False


# ---------------------------------------------------------------------------
# cache.clear_image()
# ---------------------------------------------------------------------------


async def test_clear_image_resets_path_and_verified():
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])
    await cache.update_image_and_verify(wine.wine_id, "/img/bottle.jpg")

    await cache.clear_image(wine.wine_id)

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path is None
    assert record.verified is False


async def test_clear_image_noop_for_missing_record():
    await cache.clear_image("no-such-id")  # must not raise


# ---------------------------------------------------------------------------
# cache.update_fields()
# ---------------------------------------------------------------------------


async def test_update_fields_happy_path():
    wine = _wine()
    await cache.write(wine, None, None, [])
    record = await cache.update_fields(wine.wine_id, {"name": "Updated Name", "vintage": "2021"})
    assert record is not None
    assert record.name == "Updated Name"
    assert record.vintage == "2021"
    assert record.producer == wine.producer  # unchanged


async def test_update_fields_not_found():
    result = await cache.update_fields("no-such-id", {"name": "Whatever"})
    assert result is None


# ---------------------------------------------------------------------------
# POST /wines/{wine_id}/image
# ---------------------------------------------------------------------------


async def test_upload_wine_image_happy_path(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.post(
        f"/wines/{wine.wine_id}/image",
        files={"file": ("bottle.jpg", make_jpeg(), "image/jpeg")},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["wine_id"] == wine.wine_id
    assert body["image_url"] == f"/wines/{wine.wine_id}/image"
    # Verify the image_path was updated in cache
    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path is not None


async def test_upload_wine_image_not_found(client):
    r = await client.post(
        "/wines/no-such-id/image",
        files={"file": ("bottle.jpg", make_jpeg(), "image/jpeg")},
    )
    assert r.status_code == 404


async def test_upload_wine_image_wrong_content_type(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])
    r = await client.post(
        f"/wines/{wine.wine_id}/image",
        files={"file": ("photo.png", b"fake-png-data", "image/png")},
    )
    assert r.status_code == 400


async def test_upload_wine_image_too_large(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])
    big_data = b"x" * (10 * 1024 * 1024 + 1)
    r = await client.post(
        f"/wines/{wine.wine_id}/image",
        files={"file": ("big.jpg", big_data, "image/jpeg")},
    )
    assert r.status_code == 413


async def test_upload_wine_image_invalid_magic_bytes(client, tmp_path, monkeypatch):
    # Content-Type header claims JPEG but the file bytes are not a JPEG.
    # The magic byte check (\xff\xd8) must catch this regardless of declared type.
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])
    not_a_jpeg = b"PNG\r\n\x1a\n" + b"\x00" * 100  # PNG-like header, not JPEG
    r = await client.post(
        f"/wines/{wine.wine_id}/image",
        files={"file": ("sneaky.jpg", not_a_jpeg, "image/jpeg")},
    )
    assert r.status_code == 400


# ---------------------------------------------------------------------------
# PATCH /wines/{wine_id}
# ---------------------------------------------------------------------------


async def test_patch_wine_happy_path(client):
    wine = _wine()
    await cache.write(wine, None, None, [])
    r = await client.patch(
        f"/wines/{wine.wine_id}",
        json={"name": "New Name", "vintage": "2022"},
    )
    assert r.status_code == 200
    body = r.json()
    assert body["name"] == "New Name"
    assert body["vintage"] == "2022"
    assert body["producer"] == wine.producer  # unchanged


async def test_patch_wine_not_found(client):
    r = await client.patch("/wines/no-such-id", json={"name": "Whatever"})
    assert r.status_code == 404


async def test_patch_wine_empty_body(client):
    wine = _wine()
    await cache.write(wine, None, None, [])
    r = await client.patch(f"/wines/{wine.wine_id}", json={})
    assert r.status_code == 200
    body = r.json()
    assert body["name"] == wine.name
    assert body["producer"] == wine.producer


async def test_patch_wine_image_url_versioned(client):
    """PATCH /wines/{id} returns a versioned image_url when the wine has an image."""
    wine = _wine()
    await cache.write(wine, "/img/bottle.jpg", None, [])

    r = await client.patch(f"/wines/{wine.wine_id}", json={"name": "Patched Name"})
    assert r.status_code == 200
    body = r.json()
    assert body["image_url"] is not None
    assert body["image_url"].startswith(f"/wines/{wine.wine_id}/image?v=")
    ts = body["image_url"].split("?v=")[1]
    assert ts.isdigit() and int(ts) > 0, f"Expected a positive integer timestamp, got: {ts!r}"


async def test_patch_wine_image_url_null_when_no_image(client):
    """PATCH /wines/{id} returns null image_url when the wine has no image."""
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.patch(f"/wines/{wine.wine_id}", json={"name": "Patched"})
    assert r.status_code == 200
    assert r.json()["image_url"] is None


# ---------------------------------------------------------------------------
# GET /wines/search — status filter, verified_total, sort
# ---------------------------------------------------------------------------


async def test_search_status_verified_filter(client):
    wine_v = _wine("Verified Wine", "Winery A", "2019")
    wine_u = _wine("Unverified Wine", "Winery B", "2020")
    await cache.write(wine_v, "/img/v.jpg", None, [])
    await cache.write(wine_u, "/img/u.jpg", None, [])
    await client.post("/curate", json={"wine_id": wine_v.wine_id, "verified": True})

    r = await client.get("/wines/search", params={"status": "verified"})
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 1
    assert body["results"][0]["name"] == "Verified Wine"


async def test_search_status_unverified_filter(client):
    wine_v = _wine("Verified Wine", "Winery A", "2019")
    wine_u = _wine("Unverified Wine", "Winery B", "2020")
    await cache.write(wine_v, "/img/v.jpg", None, [])
    await cache.write(wine_u, "/img/u.jpg", None, [])
    await client.post("/curate", json={"wine_id": wine_v.wine_id, "verified": True})

    r = await client.get("/wines/search", params={"status": "unverified"})
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 1
    assert body["results"][0]["name"] == "Unverified Wine"


async def test_search_status_no_image_filter(client):
    wine_img = _wine("Has Image", "A", "2019")
    wine_no = _wine("No Image", "B", "2020")
    await cache.write(wine_img, "/img/a.jpg", None, [])
    await cache.write(wine_no, None, None, [])

    r = await client.get("/wines/search", params={"status": "no_image"})
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 1
    assert body["results"][0]["name"] == "No Image"


async def test_search_verified_total_field(client):
    wine1 = _wine("Wine A", "Winery A", "2019")
    wine2 = _wine("Wine B", "Winery B", "2020")
    await cache.write(wine1, None, None, [])
    await cache.write(wine2, None, None, [])
    await client.post("/curate", json={"wine_id": wine1.wine_id, "verified": True})

    r = await client.get("/wines/search")
    assert r.status_code == 200
    body = r.json()
    assert body["total"] == 2
    assert body["verified_total"] == 1


async def test_search_sort_name_asc(client):
    await cache.write(_wine("Zinfandel", "Z Winery", "2019"), None, None, [])
    await cache.write(_wine("Chardonnay", "C Winery", "2020"), None, None, [])

    r = await client.get("/wines/search", params={"sort": "name", "order": "asc"})
    assert r.status_code == 200
    names = [rec["name"] for rec in r.json()["results"]]
    assert names == sorted(names)


# ---------------------------------------------------------------------------
# GET /wines/{wine_id}/image — Cache-Control header
# ---------------------------------------------------------------------------


async def test_get_image_cache_control_header(client, tmp_path):
    img = tmp_path / "bottle.jpg"
    img.write_bytes(b"fake-jpeg-content")
    wine = _wine()
    await cache.write(wine, str(img), None, [])

    r = await client.get(f"/wines/{wine.wine_id}/image")
    assert r.status_code == 200
    assert r.headers["cache-control"] == "public, no-cache"


async def test_search_sort_name_desc(client):
    await cache.write(_wine("Zinfandel", "Z Winery", "2019"), None, None, [])
    await cache.write(_wine("Chardonnay", "C Winery", "2020"), None, None, [])

    r = await client.get("/wines/search", params={"sort": "name", "order": "desc"})
    assert r.status_code == 200
    names = [rec["name"] for rec in r.json()["results"]]
    assert names == sorted(names, reverse=True)


async def test_search_sort_producer_asc(client):
    await cache.write(_wine("Wine A", "Zanzibar Winery", "2019"), None, None, [])
    await cache.write(_wine("Wine B", "Amalfi Winery", "2020"), None, None, [])

    r = await client.get("/wines/search", params={"sort": "producer", "order": "asc"})
    assert r.status_code == 200
    producers = [rec["producer"] for rec in r.json()["results"]]
    assert producers == sorted(producers)


# ---------------------------------------------------------------------------
# Cache key formula (D11)
# ---------------------------------------------------------------------------


async def test_cache_key_formula():
    """sha256(lower(producer) + ":" + lower(name) + ":" + (vintage or "nv"))"""
    wine = WineObject(
        name="Château Margaux", producer="Château Margaux", vintage="2018", confidence=0.9
    )
    raw = "château margaux:château margaux:2018"
    expected = hashlib.sha256(raw.encode()).hexdigest()
    assert wine.wine_id == expected


async def test_cache_key_none_producer_falls_back_to_name():
    """None producer normalizes to name so wine_id matches a record with producer == name."""
    wine_no_prod = WineObject(name="Opus One", producer=None, vintage="2019", confidence=0.9)
    wine_self_prod = WineObject(
        name="Opus One", producer="Opus One", vintage="2019", confidence=0.9
    )
    assert wine_no_prod.wine_id == wine_self_prod.wine_id


async def test_cache_key_collision_different_producers():
    """Different producers for the same wine name produce different wine_ids."""
    wine_a = WineObject(name="Pinot Noir", producer="Winery A", vintage="2020", confidence=0.9)
    wine_b = WineObject(name="Pinot Noir", producer="Winery B", vintage="2020", confidence=0.9)
    assert wine_a.wine_id != wine_b.wine_id


# ---------------------------------------------------------------------------
# Sort by verified
# ---------------------------------------------------------------------------


async def test_search_sort_verified_first(client):
    """?sort=verified&order=desc puts verified wines before unverified."""
    wine_a = _wine("Unverified Wine", "Winery A", "2019")
    wine_b = _wine("Verified Wine", "Winery B", "2020")
    await cache.write(wine_a, None, None, [])
    await cache.write(wine_b, None, None, [])
    await client.post("/curate", json={"wine_id": wine_b.wine_id, "verified": True})

    r = await client.get("/wines/search", params={"sort": "verified", "order": "desc"})
    assert r.status_code == 200
    names = [rec["name"] for rec in r.json()["results"]]
    assert names[0] == "Verified Wine", f"verified wine should sort first; got: {names}"


async def test_search_sort_verified_last(client):
    """?sort=verified&order=asc puts unverified wines before verified ones."""
    wine_a = _wine("Unverified Wine", "Winery A", "2019")
    wine_b = _wine("Verified Wine", "Winery B", "2020")
    await cache.write(wine_a, None, None, [])
    await cache.write(wine_b, None, None, [])
    await client.post("/curate", json={"wine_id": wine_b.wine_id, "verified": True})

    r = await client.get("/wines/search", params={"sort": "verified", "order": "asc"})
    assert r.status_code == 200
    names = [rec["name"] for rec in r.json()["results"]]
    assert names[0] == "Unverified Wine", (
        f"unverified wine should sort first with asc; got: {names}"
    )
