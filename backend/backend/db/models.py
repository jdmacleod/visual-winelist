import json
from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, Index, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class WineCacheRecord(Base):
    __tablename__ = "wine_cache"

    wine_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(512))
    producer: Mapped[str | None] = mapped_column(String(512), nullable=True)
    vintage: Mapped[str | None] = mapped_column(String(4), nullable=True)
    variety: Mapped[str | None] = mapped_column(String(256), nullable=True)
    appellation: Mapped[str | None] = mapped_column(String(256), nullable=True)
    image_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    tasting_note: Mapped[str | None] = mapped_column(Text, nullable=True)
    _pairings: Mapped[str | None] = mapped_column("pairings", Text, nullable=True)
    verified: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        onupdate=lambda: datetime.now(UTC),
    )

    @property
    def pairings(self) -> list[str]:
        if self._pairings is None:
            return []
        result: list[str] = json.loads(self._pairings)
        return result

    @pairings.setter
    def pairings(self, value: list[str]) -> None:
        self._pairings = json.dumps(value)


class ScanLog(Base):
    __tablename__ = "scan_log"

    scan_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
    )
    wine_count: Mapped[int] = mapped_column(Integer, default=0)
    cache_hits: Mapped[int] = mapped_column(Integer, default=0)
    ollama_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    image_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sommelier_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)


class ScanTelemetryRecord(Base):
    """Client-reported scan diagnostics (opt-in). Indexed scalar dims for queries
    plus the full JSON payload for lossless inspection and schema evolution."""

    __tablename__ = "scan_telemetry"

    # GET /telemetry/scans sorts by timestamp (default, unfiltered) and can filter
    # by outcome. The composite (outcome, timestamp) serves the filtered listing
    # and the outcome-equality lookup (its leading column); the standalone
    # timestamp index (index=True below) serves the default newest-first listing.
    # See E14 in TODOS / the matching DDL in db/session.py for existing DBs.
    __table_args__ = (Index("ix_scan_telemetry_outcome_timestamp", "outcome", "timestamp"),)

    scan_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
        index=True,
    )
    outcome: Mapped[str] = mapped_column(String(16), default="completed")
    app_version: Mapped[str | None] = mapped_column(String(32), nullable=True)
    git_sha: Mapped[str | None] = mapped_column(String(64), nullable=True)
    device_model: Mapped[str | None] = mapped_column(String(64), nullable=True)
    wine_count: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ttfb_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    first_wine_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ollama_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    payload: Mapped[str] = mapped_column(Text)
