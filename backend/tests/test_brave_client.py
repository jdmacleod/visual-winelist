"""
Tests for BraveSearchClient.
All tests mock at the httpx transport layer — no Brave API key required.
"""

import asyncio
import json
from io import BytesIO
from typing import Any
from unittest.mock import patch

import httpx
import pytest
from PIL import Image as _PIL

from backend.models.wine import WineObject
from backend.services import brave_client

# Minimal valid JPEG (magic bytes + some padding) for tests that don't need real pixels.
_FAKE_JPEG = b"\xff\xd8\xff\xe0fake-jpeg-content"


def _make_png_bytes(size: tuple[int, int] = (1, 1)) -> bytes:
    buf = BytesIO()
    _PIL.new("RGB", size, color=(255, 0, 0)).save(buf, "PNG")
    return buf.getvalue()


def _make_webp_bytes(size: tuple[int, int] = (1, 1)) -> bytes:
    buf = BytesIO()
    _PIL.new("RGB", size, color=(0, 255, 0)).save(buf, "WEBP")
    return buf.getvalue()


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def reset_rate_limiter():
    """Reset rate-limiter state before each test to avoid cross-test interference."""
    brave_client._last_search_time = 0.0
    yield
    brave_client._last_search_time = 0.0


def _make_wine(
    name: str = "Château Margaux",
    producer: str | None = "Château Margaux",
    vintage: str | None = "2018",
    variety: str | None = "Cabernet Sauvignon blend",
) -> WineObject:
    return WineObject(
        name=name,
        producer=producer,
        vintage=vintage,
        variety=variety,
        confidence=0.9,
    )


def _brave_response(results: list[dict[str, Any]]) -> bytes:
    return json.dumps({"results": results}).encode()


def _make_result(
    thumb_url: str,
    width: int | None = 400,
    height: int | None = 600,
) -> dict[str, Any]:
    return {
        "thumbnail": {"src": thumb_url},
        "properties": {"url": thumb_url, "width": width, "height": height},
    }


class _MockSearchTransport(httpx.AsyncBaseTransport):
    """Returns a canned Brave search response for the search endpoint."""

    def __init__(
        self,
        search_body: bytes = b'{"results":[]}',
        search_status: int = 200,
        image_body: bytes = _FAKE_JPEG,
        image_status: int = 200,
        image_content_length: str | None = None,
    ):
        self.search_body = search_body
        self.search_status = search_status
        self.image_body = image_body
        self.image_status = image_status
        self.image_content_length = image_content_length
        self.search_requests: list[httpx.Request] = []
        self.image_requests: list[httpx.Request] = []

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        if "search.brave.com" in str(request.url):
            self.search_requests.append(request)
            return httpx.Response(self.search_status, content=self.search_body)
        else:
            self.image_requests.append(request)
            headers = {}
            if self.image_content_length is not None:
                headers["content-length"] = self.image_content_length
            return httpx.Response(self.image_status, content=self.image_body, headers=headers)


def _with_transport(transport: _MockSearchTransport):
    return patch(
        "backend.services.brave_client._make_http_client",
        side_effect=lambda timeout: httpx.AsyncClient(transport=transport),
    )


# ---------------------------------------------------------------------------
# Portrait ranking
# ---------------------------------------------------------------------------


def test_portrait_score_tall_image():
    result = _make_result("http://example.com/tall.jpg", width=400, height=600)
    assert brave_client._portrait_score(result) == pytest.approx(1.5)


def test_portrait_score_wide_image():
    result = _make_result("http://example.com/wide.jpg", width=600, height=400)
    assert brave_client._portrait_score(result) == pytest.approx(400 / 600)


def test_portrait_score_missing_dimensions():
    result = {"thumbnail": {"src": "http://example.com/x.jpg"}, "properties": {}}
    assert brave_client._portrait_score(result) == -1.0


def test_portrait_score_zero_width():
    result = _make_result("http://example.com/x.jpg", width=0, height=500)
    assert brave_client._portrait_score(result) == -1.0


def test_portrait_ranking_order():
    results = [
        _make_result("http://example.com/a.jpg", width=400, height=300),  # score 0.75 (landscape)
        _make_result("http://example.com/b.jpg", width=400, height=800),  # score 2.0  (portrait)
        _make_result("http://example.com/c.jpg", width=400, height=600),  # score 1.5  (portrait)
        {
            "thumbnail": {"src": "http://example.com/d.jpg"},
            "properties": {},
        },  # score -1.0
    ]
    ranked = sorted(results, key=brave_client._portrait_score, reverse=True)
    urls = [(r.get("thumbnail") or {}).get("src") for r in ranked]
    assert urls == [
        "http://example.com/b.jpg",
        "http://example.com/c.jpg",
        "http://example.com/a.jpg",
        "http://example.com/d.jpg",
    ]


# ---------------------------------------------------------------------------
# Query building
# ---------------------------------------------------------------------------


def test_build_query_with_all_fields():
    wine = _make_wine(producer="Opus One", variety="Cabernet Blend", vintage="2019")
    assert brave_client._build_query(wine) == "Opus One Cabernet Blend 2019 wine bottle"


def test_build_query_no_producer_falls_back_to_name():
    wine = _make_wine(name="Petrus", producer=None, variety=None, vintage="2015")
    assert brave_client._build_query(wine) == "Petrus 2015 wine bottle"


def test_build_query_no_optional_fields():
    wine = _make_wine(producer="Screaming Eagle", variety=None, vintage=None)
    assert brave_client._build_query(wine) == "Screaming Eagle wine bottle"


# ---------------------------------------------------------------------------
# D3: Content-Length pre-check
# ---------------------------------------------------------------------------


async def test_content_length_too_large_skipped(tmp_path):
    big_size = str(3 * 1024 * 1024)  # 3MB > 2MB limit
    search_body = _brave_response([_make_result("http://cdn.example.com/big.jpg")])
    transport = _MockSearchTransport(
        search_body=search_body,
        image_body=b"x" * 1000,
        image_content_length=big_size,
    )
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    # Candidate skipped due to Content-Length — no image found
    assert result is None


async def test_content_length_within_limit_succeeds(tmp_path):
    small_size = str(500 * 1024)  # 500KB < 2MB limit
    search_body = _brave_response([_make_result("http://cdn.example.com/ok.jpg")])
    transport = _MockSearchTransport(
        search_body=search_body,
        image_body=_FAKE_JPEG,
        image_content_length=small_size,
    )
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    assert result is not None
    assert result.placeholder is False


async def test_stream_abort_no_content_length(tmp_path):
    """Stream of chunks exceeding 2MB without Content-Length header is aborted."""
    chunk = b"x" * 65536
    # 33 chunks × 64KB = ~2.1MB → should abort
    big_body = chunk * 33

    search_body = _brave_response([_make_result("http://cdn.example.com/chunked.jpg")])
    transport = _MockSearchTransport(
        search_body=search_body,
        image_body=big_body,
        image_content_length=None,
    )
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    assert result is None


# ---------------------------------------------------------------------------
# Rate limiter
# ---------------------------------------------------------------------------


async def test_rate_limiter_waits_when_called_immediately():
    """If called again within 1 second, asyncio.sleep is invoked with ~1s delay."""
    # Set _last_search_time to "just now" so elapsed ≈ 0
    loop = asyncio.get_running_loop()
    brave_client._last_search_time = loop.time()

    sleep_calls: list[float] = []

    async def mock_sleep(delay: float) -> None:
        sleep_calls.append(delay)

    with patch("backend.services.brave_client.asyncio.sleep", side_effect=mock_sleep):
        await brave_client._wait_for_rate_limit()

    assert len(sleep_calls) == 1
    assert sleep_calls[0] == pytest.approx(1.0, abs=0.05)


async def test_rate_limiter_no_wait_when_enough_time_elapsed():
    """If more than 1 second has elapsed, asyncio.sleep is NOT called."""
    # Set _last_search_time to 2 seconds ago
    loop = asyncio.get_running_loop()
    brave_client._last_search_time = loop.time() - 2.0

    sleep_calls: list[float] = []

    async def mock_sleep(delay: float) -> None:
        sleep_calls.append(delay)

    with patch("backend.services.brave_client.asyncio.sleep", side_effect=mock_sleep):
        await brave_client._wait_for_rate_limit()

    assert sleep_calls == []


# ---------------------------------------------------------------------------
# fetch_image happy path
# ---------------------------------------------------------------------------


async def test_fetch_image_success_returns_image_event(tmp_path):
    search_body = _brave_response(
        [
            _make_result("http://cdn.example.com/bottle.jpg", width=300, height=700),
        ]
    )
    transport = _MockSearchTransport(search_body=search_body, image_body=_FAKE_JPEG)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    assert result is not None
    assert result.placeholder is False
    assert result.wine_id == _make_wine().wine_id
    assert result.url == f"/wines/{_make_wine().wine_id}/image"


async def test_fetch_image_saves_to_disk(tmp_path):
    search_body = _brave_response(
        [
            _make_result("http://cdn.example.com/bottle.jpg"),
        ]
    )
    transport = _MockSearchTransport(search_body=search_body, image_body=_FAKE_JPEG)

    wine = _make_wine()
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        await brave_client.fetch_image(wine)

    cached_path = tmp_path / f"{wine.wine_id}.jpg"
    assert cached_path.exists()
    assert cached_path.read_bytes() == _FAKE_JPEG


async def test_fetch_image_sends_api_key(tmp_path):
    search_body = _brave_response([_make_result("http://cdn.example.com/bottle.jpg")])
    transport = _MockSearchTransport(search_body=search_body, image_body=_FAKE_JPEG)

    with (
        patch("backend.config.BRAVE_API_KEY", "my-secret-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        await brave_client.fetch_image(_make_wine())

    assert transport.search_requests
    req = transport.search_requests[0]
    assert req.headers.get("x-subscription-token") == "my-secret-key"


# ---------------------------------------------------------------------------
# fetch_image failure paths
# ---------------------------------------------------------------------------


async def test_fetch_image_no_api_key():
    with patch("backend.config.BRAVE_API_KEY", ""):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_brave_returns_empty_results(tmp_path):
    transport = _MockSearchTransport(search_body=b'{"results":[]}')
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_brave_non_200(tmp_path):
    transport = _MockSearchTransport(search_status=429, search_body=b"rate limited")
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_all_candidates_fail_returns_none(tmp_path):
    """All 8 image downloads return 404 → fetch_image returns None."""
    results = [
        _make_result(f"http://cdn.example.com/{i}.jpg", width=300, height=600) for i in range(8)
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(
        search_body=search_body,
        image_status=404,
        image_body=b"not found",
    )
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    assert result is None
    # Should have tried up to 8 candidates
    assert len(transport.image_requests) <= 8


async def test_fetch_image_picks_portrait_over_landscape(tmp_path):
    """Portrait candidates (h/w > 1.2) are ranked above landscape ones."""
    results = [
        _make_result("http://cdn.example.com/landscape.jpg", width=800, height=400),  # score 0.5
        _make_result("http://cdn.example.com/portrait.jpg", width=300, height=700),  # score 2.33
    ]
    search_body = _brave_response(results)

    portrait_bytes = b"\xff\xd8\xff\xe0portrait"
    landscape_bytes = b"\xff\xd8\xff\xe0landscape"

    class _OrderedTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            if "search.brave.com" in str(request.url):
                return httpx.Response(200, content=search_body)
            elif "portrait" in str(request.url):
                return httpx.Response(200, content=portrait_bytes)
            else:
                return httpx.Response(200, content=landscape_bytes)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch(
            "backend.services.brave_client._make_http_client",
            side_effect=lambda timeout: httpx.AsyncClient(transport=_OrderedTransport()),
        ),
    ):
        result = await brave_client.fetch_image(_make_wine())

    wine = _make_wine()
    cached_path = tmp_path / f"{wine.wine_id}.jpg"
    assert cached_path.read_bytes() == portrait_bytes
    assert result is not None
    assert result.placeholder is False


# ---------------------------------------------------------------------------
# T2: Pillow format normalization
# ---------------------------------------------------------------------------


async def test_download_image_png_converted_to_jpeg(tmp_path):
    """PNG from Brave CDN is converted to JPEG before saving."""
    png_bytes = _make_png_bytes()
    search_body = _brave_response([_make_result("http://cdn.example.com/bottle.png")])
    transport = _MockSearchTransport(search_body=search_body, image_body=png_bytes)

    wine = _make_wine()
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(wine)

    assert result is not None
    cached = (tmp_path / f"{wine.wine_id}.jpg").read_bytes()
    assert cached[:2] == b"\xff\xd8"


async def test_download_image_webp_converted_to_jpeg(tmp_path):
    """WebP from Brave CDN is converted to JPEG before saving."""
    webp_bytes = _make_webp_bytes()
    search_body = _brave_response([_make_result("http://cdn.example.com/bottle.webp")])
    transport = _MockSearchTransport(search_body=search_body, image_body=webp_bytes)

    wine = _make_wine()
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(wine)

    assert result is not None
    cached = (tmp_path / f"{wine.wine_id}.jpg").read_bytes()
    assert cached[:2] == b"\xff\xd8"


async def test_download_image_unreadable_bytes_returns_none(tmp_path):
    """Bytes that are not a valid image format cause the candidate to be skipped."""
    search_body = _brave_response([_make_result("http://cdn.example.com/bad.img")])
    transport = _MockSearchTransport(search_body=search_body, image_body=b"not-an-image")

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    assert result is None


# ---------------------------------------------------------------------------
# T3: fetch_image_candidates (new in this PR — lines 123-176)
# ---------------------------------------------------------------------------


async def test_fetch_image_candidates_no_api_key():
    """Returns ([], query) immediately when BRAVE_API_KEY is empty."""
    with patch("backend.config.BRAVE_API_KEY", ""):
        candidates, query = await brave_client.fetch_image_candidates(_make_wine())
    assert candidates == []
    assert isinstance(query, str)


async def test_fetch_image_candidates_returns_list():
    """Returns up to limit candidate dicts and the used query on success."""
    results = [
        {
            "thumbnail": {"src": f"http://cdn.example.com/thumb{i}.jpg"},
            "properties": {
                "url": f"http://cdn.example.com/img{i}.jpg",
                "width": 300,
                "height": 600,
            },
            "title": f"Wine {i}",
            "url": f"http://www.source{i}.com/wine",
        }
        for i in range(5)
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(search_body=search_body)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        _with_transport(transport),
    ):
        candidates, query = await brave_client.fetch_image_candidates(_make_wine(), limit=3)

    assert len(candidates) == 3
    assert isinstance(query, str)
    # Each candidate must have the expected shape
    for c in candidates:
        assert "url" in c
        assert "thumbnail_url" in c
        assert "title" in c
        assert "source_url" in c
        assert "width" in c
        assert "height" in c


async def test_fetch_image_candidates_brave_non_200():
    """Returns ([], query) when Brave returns a non-200 status."""
    transport = _MockSearchTransport(search_status=429, search_body=b"rate limited")
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        _with_transport(transport),
    ):
        candidates, query = await brave_client.fetch_image_candidates(_make_wine())
    assert candidates == []
    assert isinstance(query, str)


async def test_fetch_image_candidates_invalid_json():
    """Returns ([], query) when the Brave response body is not valid JSON."""
    transport = _MockSearchTransport(search_body=b"not-json")
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        _with_transport(transport),
    ):
        candidates, query = await brave_client.fetch_image_candidates(_make_wine())
    assert candidates == []
    assert isinstance(query, str)


async def test_fetch_image_candidates_network_exception():
    """Returns ([], query) on network error."""
    import httpx as _httpx

    class _FailTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            raise _httpx.ConnectError("refused")

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch(
            "backend.services.brave_client._make_http_client",
            side_effect=lambda timeout: httpx.AsyncClient(transport=_FailTransport()),
        ),
    ):
        candidates, query = await brave_client.fetch_image_candidates(_make_wine())
    assert candidates == []
    assert isinstance(query, str)


async def test_fetch_image_candidates_custom_query_used():
    """Custom query overrides the default _build_query result."""
    transport = _MockSearchTransport(search_body=b'{"results":[]}')
    custom_q = "my custom search"
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        _with_transport(transport),
    ):
        candidates, query = await brave_client.fetch_image_candidates(_make_wine(), query=custom_q)
    assert query == custom_q
    assert transport.search_requests[0].url.params["q"] == custom_q


async def test_fetch_image_candidates_skips_result_with_no_urls():
    """Candidates without thumbnail or url are skipped."""
    results = [
        {"thumbnail": {}, "properties": {}, "title": "No URL"},  # no src, no url → skip
        {
            "thumbnail": {"src": "http://cdn.example.com/t.jpg"},
            "properties": {"url": "http://cdn.example.com/img.jpg", "width": 300, "height": 600},
            "title": "Good Result",
            "url": "http://source.com/wine",
        },
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(search_body=search_body)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        _with_transport(transport),
    ):
        candidates, _ = await brave_client.fetch_image_candidates(_make_wine())

    assert len(candidates) == 1
    assert candidates[0]["title"] == "Good Result"


async def test_fetch_image_candidates_portrait_ranked_first():
    """Portrait-shaped candidates (tall h/w ratio) appear first in results."""
    results = [
        {
            "thumbnail": {"src": "http://cdn.example.com/landscape.jpg"},
            "properties": {
                "url": "http://cdn.example.com/landscape.jpg",
                "width": 800,
                "height": 400,
            },
            "title": "Landscape",
            "url": "http://source.com/landscape",
        },
        {
            "thumbnail": {"src": "http://cdn.example.com/portrait.jpg"},
            "properties": {
                "url": "http://cdn.example.com/portrait.jpg",
                "width": 300,
                "height": 700,
            },
            "title": "Portrait",
            "url": "http://source.com/portrait",
        },
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(search_body=search_body)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        _with_transport(transport),
    ):
        candidates, _ = await brave_client.fetch_image_candidates(_make_wine())

    assert len(candidates) == 2
    assert candidates[0]["title"] == "Portrait"
    assert candidates[1]["title"] == "Landscape"


# ---------------------------------------------------------------------------
# T4: fetch_image edge cases (remaining uncovered paths)
# ---------------------------------------------------------------------------


async def test_fetch_image_brave_network_exception(tmp_path):
    """Returns None when the Brave API call raises a network error."""
    import httpx as _httpx

    class _FailTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            raise _httpx.ConnectError("refused")

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        patch(
            "backend.services.brave_client._make_http_client",
            side_effect=lambda timeout: httpx.AsyncClient(transport=_FailTransport()),
        ),
    ):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_brave_json_decode_error(tmp_path):
    """Returns None when Brave response body is not valid JSON."""
    transport = _MockSearchTransport(search_body=b"not-json")
    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_skips_candidate_without_thumb_url(tmp_path):
    """A candidate with no thumbnail.src is skipped; next candidate is tried."""
    results = [
        {
            "thumbnail": {},  # no src → skip
            "properties": {
                "url": "http://cdn.example.com/no-thumb.jpg",
                "width": 300,
                "height": 600,
            },
        },
        _make_result("http://cdn.example.com/ok.jpg", width=300, height=600),
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(search_body=search_body, image_body=_FAKE_JPEG)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
    ):
        result = await brave_client.fetch_image(_make_wine())

    assert result is not None  # second candidate succeeded


async def test_fetch_image_oserror_on_save_tries_next_candidate(tmp_path):
    """OSError writing to disk causes the candidate to be skipped, not a crash."""
    results = [
        _make_result("http://cdn.example.com/a.jpg", width=300, height=600),
        _make_result("http://cdn.example.com/b.jpg", width=300, height=600),
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(search_body=search_body, image_body=_FAKE_JPEG)

    call_count = 0

    original_open = open  # noqa: WPS421 (builtins)

    def _flaky_open(path, mode="r", **kwargs):
        nonlocal call_count
        if "wb" in mode and call_count == 0:
            call_count += 1
            raise OSError("disk full")
        return original_open(path, mode, **kwargs)

    with (
        patch("backend.config.BRAVE_API_KEY", "test-key"),
        patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)),
        _with_transport(transport),
        patch("builtins.open", side_effect=_flaky_open),
    ):
        result = await brave_client.fetch_image(_make_wine())

    # Second candidate should succeed after the first write fails
    assert result is not None
