import json
from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, String, Text
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
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
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
