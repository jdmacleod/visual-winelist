"""
Tests for new wines.py endpoints: image-candidates, image-from-url, DELETE /image,
variant serving (GET /wines/{id}/image?size=thumb|card|detail), and helpers.
All tests use the per-test SQLite DB from conftest.use_test_db.
"""

from io import BytesIO
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from PIL import Image as _PIL

from backend.models.wine import WineObject
from backend.services import cache
from tests.conftest import make_jpeg


def _make_real_jpeg(size: tuple[int, int] = (100, 200)) -> bytes:
    """Return a real JPEG file (not just magic bytes) for Pillow-based tests."""
    buf = BytesIO()
    _PIL.new("RGB", size, color=(120, 60, 30)).save(buf, "JPEG")
    return buf.getvalue()


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


# ---------------------------------------------------------------------------
# GET /wines/{wine_id}/image?size= — variant serving (new in this PR)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("size", ["thumb", "card", "detail"])
async def test_get_wine_image_variant_generates_webp(client, tmp_path, monkeypatch, size):
    """Requesting a named size generates a WebP variant and returns image/webp."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    img_path = tmp_path / "bottle.jpg"
    img_path.write_bytes(_make_real_jpeg())
    wine = _wine()
    await cache.write(wine, str(img_path), None, [])

    r = await client.get(f"/wines/{wine.wine_id}/image?size={size}")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("image/webp")
    # Variant file should now exist
    variant = tmp_path / f"{wine.wine_id}_{size}.webp"
    assert variant.exists()


async def test_get_wine_image_variant_served_from_cache_on_second_request(
    client, tmp_path, monkeypatch
):
    """Second request for a variant skips _generate_variant (file already exists)."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    img_path = tmp_path / "bottle.jpg"
    img_path.write_bytes(_make_real_jpeg())
    wine = _wine()
    await cache.write(wine, str(img_path), None, [])

    # First request generates the variant
    r1 = await client.get(f"/wines/{wine.wine_id}/image?size=thumb")
    assert r1.status_code == 200

    # Second request should also succeed (served from cached file)
    r2 = await client.get(f"/wines/{wine.wine_id}/image?size=thumb")
    assert r2.status_code == 200


async def test_get_wine_image_variant_oserror_returns_500(client, tmp_path, monkeypatch):
    """If _generate_variant raises OSError, endpoint returns 500."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    img_path = tmp_path / "bottle.jpg"
    img_path.write_bytes(_make_real_jpeg())
    wine = _wine()
    await cache.write(wine, str(img_path), None, [])

    with patch(
        "backend.routers.wines._generate_variant",
        side_effect=OSError("disk full"),
    ):
        r = await client.get(f"/wines/{wine.wine_id}/image?size=card")

    assert r.status_code == 500
    assert r.json()["detail"] == "variant_write_failed"


async def test_get_wine_image_etag_304(client, tmp_path, monkeypatch):
    """Sending If-None-Match with matching ETag returns 304 Not Modified."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    img_path = tmp_path / "bottle.jpg"
    img_path.write_bytes(_make_real_jpeg())
    wine = _wine()
    await cache.write(wine, str(img_path), None, [])

    # First request to grab the ETag
    r1 = await client.get(f"/wines/{wine.wine_id}/image")
    assert r1.status_code == 200
    etag = r1.headers["etag"]
    assert etag

    # Second request with matching ETag should return 304
    r2 = await client.get(f"/wines/{wine.wine_id}/image", headers={"if-none-match": etag})
    assert r2.status_code == 304


# ---------------------------------------------------------------------------
# _generate_variant unit tests
# ---------------------------------------------------------------------------


def test_generate_variant_creates_webp(tmp_path):
    """_generate_variant produces a valid WebP file at the correct dimensions."""
    from backend.routers.wines import _generate_variant

    src = tmp_path / "source.jpg"
    src.write_bytes(_make_real_jpeg((400, 600)))  # 400w × 600h
    dst = tmp_path / "thumb.webp"

    _generate_variant(str(src), str(dst), width=120)

    assert dst.exists()
    img = _PIL.open(str(dst))
    assert img.format == "WEBP"
    # Width should be exactly 120; height proportional to 600/400 * 120 = 180
    assert img.size[0] == 120
    assert img.size[1] == 180


def test_generate_variant_atomic_write(tmp_path):
    """No .tmp file should remain after a successful _generate_variant call."""
    from backend.routers.wines import _generate_variant

    src = tmp_path / "source.jpg"
    src.write_bytes(_make_real_jpeg())
    dst = tmp_path / "card.webp"

    _generate_variant(str(src), str(dst), width=320)

    assert dst.exists()
    assert not (tmp_path / "card.webp.tmp").exists()


# ---------------------------------------------------------------------------
# _delete_variants unit tests
# ---------------------------------------------------------------------------


def test_delete_variants_removes_existing_files(tmp_path, monkeypatch):
    """_delete_variants deletes thumb, card, and detail WebP files when they exist."""
    import backend.config as cfg
    from backend.routers.wines import _delete_variants

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine_id = "test-wine-id"
    for size in ("thumb", "card", "detail"):
        (tmp_path / f"{wine_id}_{size}.webp").write_bytes(b"fake-webp")

    _delete_variants(wine_id)

    for size in ("thumb", "card", "detail"):
        assert not (tmp_path / f"{wine_id}_{size}.webp").exists()


def test_delete_variants_noop_when_files_missing(tmp_path, monkeypatch):
    """_delete_variants does not raise when variant files do not exist."""
    import backend.config as cfg
    from backend.routers.wines import _delete_variants

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    _delete_variants("nonexistent-wine")  # Must not raise


# ---------------------------------------------------------------------------
# POST /wines/{wine_id}/image — upload delete-then-rollback on update failure
# ---------------------------------------------------------------------------


async def test_upload_wine_image_rollback_on_cache_update_failure(client, tmp_path, monkeypatch):
    """If cache.update_image returns False, the saved file is cleaned up."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with patch("backend.routers.wines.cache.update_image", new=AsyncMock(return_value=False)):
        r = await client.post(
            f"/wines/{wine.wine_id}/image",
            files={"file": ("bottle.jpg", make_jpeg(), "image/jpeg")},
        )

    assert r.status_code == 404
    # The orphaned file should have been removed
    leftover = tmp_path / f"{wine.wine_id}.jpg"
    assert not leftover.exists()


# ---------------------------------------------------------------------------
# POST /wines/{wine_id}/image-from-url — network exception + rollback path
# ---------------------------------------------------------------------------


async def test_image_from_url_network_exception(client, tmp_path, monkeypatch):
    """Network error during image fetch returns 422 invalid_image."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    # Simulate a connection error
    client_ctx = AsyncMock()
    client_ctx.__aenter__ = AsyncMock(return_value=client_ctx)
    client_ctx.__aexit__ = AsyncMock(return_value=None)
    client_ctx.get = AsyncMock(side_effect=httpx.ConnectError("connection refused"))
    with patch("backend.routers.wines._make_url_client", return_value=client_ctx):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )

    assert r.status_code == 422
    assert r.json()["detail"] == "invalid_image"


async def test_image_from_url_rollback_on_cache_update_failure(client, tmp_path, monkeypatch):
    """If update_image_and_verify fails, the saved file is removed."""
    import backend.config as cfg

    monkeypatch.setattr(cfg, "IMAGE_CACHE_DIR", str(tmp_path))
    wine = _wine()
    await cache.write(wine, None, None, [])

    with (
        _patch_url_client(_mock_http_response(content=make_jpeg())),
        patch(
            "backend.routers.wines.cache.update_image_and_verify",
            new=AsyncMock(return_value=False),
        ),
    ):
        r = await client.post(
            f"/wines/{wine.wine_id}/image-from-url",
            json={"url": "https://cdn.example.com/img.jpg"},
        )

    assert r.status_code == 404
    leftover = tmp_path / f"{wine.wine_id}.jpg"
    assert not leftover.exists()
