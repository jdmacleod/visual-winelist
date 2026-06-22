"""
Tests for new wines.py endpoints: image-candidates, image-from-url, DELETE /image.
All tests use the per-test SQLite DB from conftest.use_test_db.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from backend.models.wine import WineObject
from backend.services import cache
from tests.conftest import make_jpeg


def _wine(
    name: str = "Château Margaux",
    producer: str | None = "Château Margaux",
    vintage: str | None = "2018",
) -> WineObject:
    return WineObject(name=name, producer=producer, vintage=vintage, confidence=0.9)


def _mock_http_response(status: int = 200, content: bytes | None = None) -> MagicMock:
    resp = MagicMock(spec=httpx.Response)
    resp.status_code = status
    resp.content = content if content is not None else make_jpeg()
    return resp


def _patch_url_client(response: MagicMock):
    """Patch _make_url_client so the GET returns `response`."""
    client_ctx = AsyncMock()
    client_ctx.__aenter__ = AsyncMock(return_value=client_ctx)
    client_ctx.__aexit__ = AsyncMock(return_value=None)
    client_ctx.get = AsyncMock(return_value=response)
    return patch("backend.routers.wines._make_url_client", return_value=client_ctx)


# ---------------------------------------------------------------------------
# GET /wines/{wine_id}/image-candidates
# ---------------------------------------------------------------------------


async def test_image_candidates_not_found(client):
    r = await client.get("/wines/no-such-id/image-candidates")
    assert r.status_code == 404


async def test_image_candidates_returns_list(client):
    wine = _wine()
    await cache.write(wine, None, None, [])

    mock_candidates = [
        {
            "url": "https://cdn.example.com/img.jpg",
            "thumbnail_url": "https://cdn.example.com/thumb.jpg",
            "title": "Château Margaux 2018 - Vivino",
            "source_url": "https://www.vivino.com/wines/123",
            "width": 300,
            "height": 500,
        }
    ]
    with patch(
        "backend.routers.wines.brave_client.fetch_image_candidates",
        new=AsyncMock(return_value=mock_candidates),
    ):
        r = await client.get(f"/wines/{wine.wine_id}/image-candidates")

    assert r.status_code == 200
    body = r.json()
    assert body["wine_id"] == wine.wine_id
    assert len(body["candidates"]) == 1
    assert body["candidates"][0]["url"] == "https://cdn.example.com/img.jpg"
    assert body["candidates"][0]["title"] == "Château Margaux 2018 - Vivino"
    assert body["candidates"][0]["source_url"] == "https://www.vivino.com/wines/123"


async def test_image_candidates_empty_when_brave_returns_nothing(client):
    wine = _wine()
    await cache.write(wine, None, None, [])

    with patch(
        "backend.routers.wines.brave_client.fetch_image_candidates",
        new=AsyncMock(return_value=[]),
    ):
        r = await client.get(f"/wines/{wine.wine_id}/image-candidates")

    assert r.status_code == 200
    assert r.json()["candidates"] == []


# ---------------------------------------------------------------------------
# POST /wines/{wine_id}/image-from-url
# ---------------------------------------------------------------------------


async def test_image_from_url_not_found(client):
    r = await client.post(
        "/wines/no-such-id/image-from-url",
        json={"url": "https://cdn.example.com/img.jpg"},
    )
    assert r.status_code == 404


async def test_image_from_url_invalid_scheme_http(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.post(
        f"/wines/{wine.wine_id}/image-from-url",
        json={"url": "http://cdn.example.com/img.jpg"},
    )
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_url"


async def test_image_from_url_private_ip_rejected(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.post(
        f"/wines/{wine.wine_id}/image-from-url",
        json={"url": "https://192.168.1.100/img.jpg"},
    )
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_url"


async def test_image_from_url_loopback_rejected(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.post(
        f"/wines/{wine.wine_id}/image-from-url",
        json={"url": "https://127.0.0.1/img.jpg"},
    )
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_url"


async def test_image_from_url_expired_403(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with _patch_url_client(_mock_http_response(status=403)):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )
    assert r.status_code == 404
    assert r.json()["detail"] == "image_expired"


async def test_image_from_url_expired_404(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with _patch_url_client(_mock_http_response(status=404)):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )
    assert r.status_code == 404
    assert r.json()["detail"] == "image_expired"


async def test_image_from_url_bad_server_response(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with _patch_url_client(_mock_http_response(status=500)):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_image"


async def test_image_from_url_invalid_jpeg_magic(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with _patch_url_client(_mock_http_response(content=b"PNG\r\n\x1a\nfake-png")):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_image"


async def test_image_from_url_too_large(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    big_jpeg = b"\xff\xd8\xff" + b"x" * (2 * 1024 * 1024 + 1)
    with _patch_url_client(_mock_http_response(content=big_jpeg)):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_image"


async def test_image_from_url_happy_path(client, tmp_path, monkeypatch):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with _patch_url_client(_mock_http_response(content=make_jpeg())):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )

    assert r.status_code == 200
    body = r.json()
    assert body["wine_id"] == wine.wine_id
    assert body["image_url"] == f"/wines/{wine.wine_id}/image"

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.verified is True
    assert record.image_path is not None


async def test_image_from_url_sets_verified_true(client, tmp_path, monkeypatch):
    """Picking a candidate via image-from-url must atomically set verified=True."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with _patch_url_client(_mock_http_response(content=make_jpeg())):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )

    assert r.status_code == 200
    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.verified is True


# ---------------------------------------------------------------------------
# DELETE /wines/{wine_id}/image
# ---------------------------------------------------------------------------


async def test_clear_wine_image_not_found(client):
    r = await client.delete("/wines/no-such-id/image")
    assert r.status_code == 404


async def test_clear_wine_image_happy_path(client, tmp_path):
    img = tmp_path / "bottle.jpg"
    img.write_bytes(make_jpeg())
    wine = _wine()
    await cache.write(wine, str(img), None, [])
    # Mark verified first to ensure clear resets it
    await cache.update_image_and_verify(wine.wine_id, str(img))

    r = await client.delete(f"/wines/{wine.wine_id}/image")
    assert r.status_code == 200
    assert r.json()["image_cleared"] is True

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path is None
    assert record.verified is False
    assert not img.exists()


async def test_clear_wine_image_no_prior_image(client):
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.delete(f"/wines/{wine.wine_id}/image")
    assert r.status_code == 200
    assert r.json()["image_cleared"] is True

    record = await cache.lookup(wine.wine_id)
    assert record is not None
    assert record.image_path is None
    assert record.verified is False


# ---------------------------------------------------------------------------
# _validate_candidate_url (unit tests — call endpoint to exercise helper)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "url",
    [
        "http://cdn.example.com/img.jpg",  # wrong scheme
        "ftp://cdn.example.com/img.jpg",  # wrong scheme
        "https://",  # no host
        "https://192.168.0.1/img.jpg",  # RFC-1918
        "https://10.0.0.1/img.jpg",  # RFC-1918
        "https://172.16.0.1/img.jpg",  # RFC-1918
        "https://127.0.0.1/img.jpg",  # loopback
        "https://[::1]/img.jpg",  # IPv6 loopback
    ],
)
async def test_validate_candidate_url_rejects_bad_urls(client, tmp_path, monkeypatch, url):
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    r = await client.post(f"/wines/{wine.wine_id}/image-from-url", json={"url": url})
    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_url"
