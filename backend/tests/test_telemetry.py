import json
from typing import Any
from unittest.mock import patch

from sqlalchemy import select as sa_select

from backend.db import session as db_session
from backend.db.models import ScanTelemetryRecord


def _payload(scan_id: str = "abc12345", **over: Any) -> dict[str, Any]:
    p: dict[str, Any] = {
        "scan_id": scan_id,
        "outcome": "completed",
        "app_version": "0.2.12.0",
        "git_sha": "deadbee",
        "device_model": "iPhone16,1",
        "ttfb_ms": 150,
        "first_wine_ms": 15000,
        "ollama_ms": 16000,
        "total_ms": 18000,
        "wine_count": 19,
        "event_timeline": [{"label": "wine[0]", "ms": 15000}],
    }
    p.update(over)
    return p


async def test_post_telemetry_writes_row(client):
    r = await client.post("/telemetry/scan", json=_payload())
    assert r.status_code == 204

    async with db_session.SessionLocal() as s:
        row = await s.scalar(
            sa_select(ScanTelemetryRecord).where(ScanTelemetryRecord.scan_id == "abc12345")
        )
    assert row is not None
    assert row.outcome == "completed"
    assert row.total_ms == 18000
    assert row.first_wine_ms == 15000
    stored = json.loads(row.payload)
    assert stored["wine_count"] == 19
    assert stored["event_timeline"][0]["label"] == "wine[0]"


async def test_post_telemetry_minimal(client):
    """Only scan_id is required; outcome defaults to completed."""
    r = await client.post("/telemetry/scan", json={"scan_id": "min00001"})
    assert r.status_code == 204
    async with db_session.SessionLocal() as s:
        row = await s.scalar(
            sa_select(ScanTelemetryRecord).where(ScanTelemetryRecord.scan_id == "min00001")
        )
    assert row is not None and row.outcome == "completed"


async def test_get_telemetry_lists_with_payload(client):
    await client.post("/telemetry/scan", json=_payload(scan_id="list0001", outcome="cancelled"))
    r = await client.get("/telemetry/scans")
    assert r.status_code == 200
    body = r.json()
    match = next(s for s in body["scans"] if s["scan_id"] == "list0001")
    assert match["outcome"] == "cancelled"
    assert "received_at" in match


async def test_get_telemetry_filter_by_outcome(client):
    await client.post("/telemetry/scan", json=_payload(scan_id="ok000001", outcome="completed"))
    await client.post("/telemetry/scan", json=_payload(scan_id="cx000001", outcome="cancelled"))
    r = await client.get("/telemetry/scans?outcome=cancelled")
    scans = r.json()["scans"]
    assert scans and all(s["outcome"] == "cancelled" for s in scans)


async def test_post_telemetry_upserts_by_scan_id(client):
    await client.post("/telemetry/scan", json=_payload(scan_id="up000001", outcome="error"))
    await client.post("/telemetry/scan", json=_payload(scan_id="up000001", outcome="completed"))
    async with db_session.SessionLocal() as s:
        rows = (
            (
                await s.execute(
                    sa_select(ScanTelemetryRecord).where(ScanTelemetryRecord.scan_id == "up000001")
                )
            )
            .scalars()
            .all()
        )
    assert len(rows) == 1, "same scan_id must upsert, not duplicate"
    assert rows[0].outcome == "completed"


async def test_post_telemetry_disabled_returns_404(client):
    with patch("backend.config.TELEMETRY_ENABLED", False):
        r = await client.post("/telemetry/scan", json=_payload(scan_id="dis00001"))
    assert r.status_code == 404


async def test_post_telemetry_rejects_bad_outcome(client):
    r = await client.post("/telemetry/scan", json={"scan_id": "bad00001", "outcome": "nope"})
    assert r.status_code == 422
