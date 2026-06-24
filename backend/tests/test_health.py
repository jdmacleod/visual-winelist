from unittest.mock import AsyncMock, patch


async def test_health_ollama_down(client):
    with patch(
        "backend.services.ollama_client.check_reachable",
        new=AsyncMock(return_value=False),
    ):
        with patch("backend.config.BRAVE_API_KEY", "test-key"):
            r = await client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "degraded"
    assert body["ollama"] is False
    assert body["brave_key"] is True
    assert body["version"]
    assert "." in body["version"]


async def test_health_all_ok(client):
    with patch(
        "backend.services.ollama_client.check_reachable",
        new=AsyncMock(return_value=True),
    ):
        with patch("backend.config.BRAVE_API_KEY", "test-key"):
            r = await client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["ollama"] is True
    assert body["version"]
    assert "." in body["version"]
