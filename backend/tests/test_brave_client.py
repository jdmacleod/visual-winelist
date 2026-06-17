"""
Tests for BraveSearchClient.
All tests mock at the httpx transport layer — no Brave API key required.
"""

import asyncio
import json
from typing import Any
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from backend.models.wine import WineObject
from backend.services import brave_client


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
        image_body: bytes = b"fake-jpeg-data",
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
            return httpx.Response(
                self.image_status, content=self.image_body, headers=headers
            )


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
        _make_result("http://example.com/a.jpg", width=400, height=300),   # score 0.75 (landscape)
        _make_result("http://example.com/b.jpg", width=400, height=800),   # score 2.0  (portrait)
        _make_result("http://example.com/c.jpg", width=400, height=600),   # score 1.5  (portrait)
        {"thumbnail": {"src": "http://example.com/d.jpg"}, "properties": {}},  # score -1.0
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
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
        result = await brave_client.fetch_image(_make_wine())

    # Candidate skipped due to Content-Length — no image found
    assert result is None


async def test_content_length_within_limit_succeeds(tmp_path):
    small_size = str(500 * 1024)  # 500KB < 2MB limit
    search_body = _brave_response([_make_result("http://cdn.example.com/ok.jpg")])
    transport = _MockSearchTransport(
        search_body=search_body,
        image_body=b"fake-jpeg",
        image_content_length=small_size,
    )
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
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
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
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
    search_body = _brave_response([
        _make_result("http://cdn.example.com/bottle.jpg", width=300, height=700),
    ])
    transport = _MockSearchTransport(search_body=search_body, image_body=b"fake-jpeg")

    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
        result = await brave_client.fetch_image(_make_wine())

    assert result is not None
    assert result.placeholder is False
    assert result.wine_id == _make_wine().wine_id
    assert result.url == f"/wines/{_make_wine().wine_id}/image"


async def test_fetch_image_saves_to_disk(tmp_path):
    image_bytes = b"fake-jpeg-content"
    search_body = _brave_response([
        _make_result("http://cdn.example.com/bottle.jpg"),
    ])
    transport = _MockSearchTransport(search_body=search_body, image_body=image_bytes)

    wine = _make_wine()
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
        await brave_client.fetch_image(wine)

    cached_path = tmp_path / f"{wine.wine_id}.jpg"
    assert cached_path.exists()
    assert cached_path.read_bytes() == image_bytes


async def test_fetch_image_sends_api_key(tmp_path):
    search_body = _brave_response([_make_result("http://cdn.example.com/bottle.jpg")])
    transport = _MockSearchTransport(search_body=search_body, image_body=b"fake-jpeg")

    with patch("backend.config.BRAVE_API_KEY", "my-secret-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
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
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_brave_non_200(tmp_path):
    transport = _MockSearchTransport(search_status=429, search_body=b"rate limited")
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
        result = await brave_client.fetch_image(_make_wine())
    assert result is None


async def test_fetch_image_all_candidates_fail_returns_none(tmp_path):
    """All 8 image downloads return 404 → fetch_image returns None."""
    results = [
        _make_result(f"http://cdn.example.com/{i}.jpg", width=300, height=600)
        for i in range(8)
    ]
    search_body = _brave_response(results)
    transport = _MockSearchTransport(
        search_body=search_body,
        image_status=404,
        image_body=b"not found",
    )
    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         _with_transport(transport):
        result = await brave_client.fetch_image(_make_wine())

    assert result is None
    # Should have tried up to 8 candidates
    assert len(transport.image_requests) <= 8


async def test_fetch_image_picks_portrait_over_landscape(tmp_path):
    """Portrait candidates (h/w > 1.2) are ranked above landscape ones."""
    results = [
        _make_result("http://cdn.example.com/landscape.jpg", width=800, height=400),  # score 0.5
        _make_result("http://cdn.example.com/portrait.jpg", width=300, height=700),   # score 2.33
    ]
    search_body = _brave_response(results)

    portrait_bytes = b"portrait-jpeg"
    landscape_bytes = b"landscape-jpeg"

    class _OrderedTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            if "search.brave.com" in str(request.url):
                return httpx.Response(200, content=search_body)
            elif "portrait" in str(request.url):
                return httpx.Response(200, content=portrait_bytes)
            else:
                return httpx.Response(200, content=landscape_bytes)

    with patch("backend.config.BRAVE_API_KEY", "test-key"), \
         patch("backend.config.IMAGE_CACHE_DIR", str(tmp_path)), \
         patch(
             "backend.services.brave_client._make_http_client",
             side_effect=lambda timeout: httpx.AsyncClient(transport=_OrderedTransport()),
         ):
        result = await brave_client.fetch_image(_make_wine())

    wine = _make_wine()
    cached_path = tmp_path / f"{wine.wine_id}.jpg"
    assert cached_path.read_bytes() == portrait_bytes
    assert result is not None
    assert result.placeholder is False
