import json
from typing import Any
from unittest.mock import patch

from sqlalchemy import select as sa_select
from sqlalchemy import text

from backend.db import session as db_session
from backend.db.models import ScanTelemetryRecord
from backend.db.session import init_db


async def _telemetry_index_names() -> set[str]:
    async with db_session.engine.begin() as conn:
        rows = await conn.execute(text("PRAGMA index_list('scan_telemetry')"))
        return {row[1] for row in rows.fetchall()}


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


async def test_get_telemetry_disabled_returns_404(client):
    """GET mirrors POST: when telemetry is disabled the listing is also off,
    so disabling the feature doesn't keep serving stored reports."""
    await client.post("/telemetry/scan", json=_payload(scan_id="getdis01"))
    with patch("backend.config.TELEMETRY_ENABLED", False):
        r = await client.get("/telemetry/scans")
    assert r.status_code == 404


async def test_get_telemetry_skips_corrupt_payload_row(client):
    """A single unparseable payload row is skipped, not allowed to 500 the whole listing."""
    await client.post("/telemetry/scan", json=_payload(scan_id="good0001"))
    # Hand-corrupt one stored payload to simulate a truncated/garbage row.
    async with db_session.SessionLocal() as s:
        bad = ScanTelemetryRecord(scan_id="corrupt1", outcome="completed", payload="{not json")
        await s.merge(bad)
        await s.commit()

    r = await client.get("/telemetry/scans")
    assert r.status_code == 200, "one bad row must not take down the endpoint"
    scan_ids = {s["scan_id"] for s in r.json()["scans"]}
    assert "good0001" in scan_ids
    assert "corrupt1" not in scan_ids


async def test_delete_telemetry_clears_all_and_reports_count(client):
    """DELETE wipes stored telemetry and returns how many rows were removed."""
    await client.post("/telemetry/scan", json=_payload(scan_id="del00001"))
    await client.post("/telemetry/scan", json=_payload(scan_id="del00002"))

    r = await client.delete("/telemetry/scans")
    assert r.status_code == 200
    assert r.json()["deleted"] == 2

    listing = await client.get("/telemetry/scans")
    assert listing.json()["count"] == 0


async def test_delete_telemetry_disabled_returns_404(client):
    """DELETE mirrors the gate: disabled telemetry can't be cleared via the API."""
    with patch("backend.config.TELEMETRY_ENABLED", False):
        r = await client.delete("/telemetry/scans")
    assert r.status_code == 404


async def test_post_telemetry_rejects_bad_outcome(client):
    r = await client.post("/telemetry/scan", json={"scan_id": "bad00001", "outcome": "nope"})
    assert r.status_code == 422


async def test_post_telemetry_best_effort_on_db_failure(client):
    """A DB write failure is swallowed — telemetry never surfaces an error to the client."""

    class _Boom:
        def __call__(self):
            raise RuntimeError("db down")

    with patch("backend.routers.telemetry.db_session.SessionLocal", _Boom()):
        r = await client.post("/telemetry/scan", json=_payload(scan_id="boom0001"))
    assert r.status_code == 204

    async with db_session.SessionLocal() as s:
        row = await s.scalar(
            sa_select(ScanTelemetryRecord).where(ScanTelemetryRecord.scan_id == "boom0001")
        )
    assert row is None, "failed write must not persist a partial row"


# --- E14: scan_telemetry listing indexes ---


async def test_fresh_db_has_telemetry_listing_indexes():
    """A DB built by create_all (the autouse fixture) carries the timestamp +
    composite indexes that back GET /telemetry/scans, and not the old standalone
    outcome index (folded into the composite's leading column)."""
    names = await _telemetry_index_names()
    assert "ix_scan_telemetry_timestamp" in names
    assert "ix_scan_telemetry_outcome_timestamp" in names
    assert "ix_scan_telemetry_outcome" not in names


async def test_init_db_creates_telemetry_indexes_on_existing_db():
    """init_db() adds the listing indexes to a DB that predates E14."""
    async with db_session.engine.begin() as conn:
        await conn.execute(text("DROP INDEX IF EXISTS ix_scan_telemetry_timestamp"))
        await conn.execute(text("DROP INDEX IF EXISTS ix_scan_telemetry_outcome_timestamp"))

    await init_db()

    names = await _telemetry_index_names()
    assert "ix_scan_telemetry_timestamp" in names
    assert "ix_scan_telemetry_outcome_timestamp" in names


async def test_init_db_drops_redundant_outcome_index():
    """An old standalone outcome index is dropped (redundant with the composite),
    and the migration is idempotent across repeated runs."""
    async with db_session.engine.begin() as conn:
        await conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_scan_telemetry_outcome ON scan_telemetry (outcome)")
        )
    assert "ix_scan_telemetry_outcome" in await _telemetry_index_names()

    await init_db()
    await init_db()  # idempotent: second run must not raise

    names = await _telemetry_index_names()
    assert "ix_scan_telemetry_outcome" not in names
    assert "ix_scan_telemetry_outcome_timestamp" in names


async def test_filtered_listing_still_works_with_new_indexes(client):
    """Functional guard: the outcome-filtered listing returns the right rows after
    the index reshape (the composite must still serve WHERE outcome = X)."""
    await client.post("/telemetry/scan", json=_payload(scan_id="idx00001", outcome="completed"))
    await client.post("/telemetry/scan", json=_payload(scan_id="idx00002", outcome="cancelled"))

    r = await client.get("/telemetry/scans", params={"outcome": "cancelled"})
    assert r.status_code == 200
    body = r.json()
    assert body["count"] == 1
    assert body["scans"][0]["scan_id"] == "idx00002"
