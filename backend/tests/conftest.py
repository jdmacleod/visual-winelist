import pytest
from httpx import ASGITransport, AsyncClient

from backend.main import app


@pytest.fixture
async def client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as c:
        yield c


def make_jpeg(size: int = 1024) -> bytes:
    """Return a minimal valid-looking JPEG payload of approximately `size` bytes."""
    # JFIF header + padding + EOI marker
    header = bytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]) + b"JFIF\x00"
    return header + b"\x00" * max(0, size - len(header) - 2) + bytes([0xFF, 0xD9])
