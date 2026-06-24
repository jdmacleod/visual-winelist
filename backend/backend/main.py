import logging
import os
import warnings
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from backend import config
from backend.db.session import init_db
from backend.routers import curate, health, scan, wines

log = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    os.makedirs(config.IMAGE_CACHE_DIR, exist_ok=True)
    await init_db()

    if not config.BRAVE_API_KEY:
        warnings.warn("BRAVE_API_KEY not set — image search will be skipped", stacklevel=2)

    if not (0 <= config.IMAGE_WEBP_QUALITY <= 100):
        raise ValueError(f"IMAGE_WEBP_QUALITY must be 0-100, got {config.IMAGE_WEBP_QUALITY}")

    log.info(
        "image config: thumb=%dpx card=%dpx detail=%dpx webp_quality=%d",
        config.IMAGE_THUMB_WIDTH,
        config.IMAGE_CARD_WIDTH,
        config.IMAGE_DETAIL_WIDTH,
        config.IMAGE_WEBP_QUALITY,
    )

    yield


app = FastAPI(title="visual-winelist backend", version=config.APP_VERSION, lifespan=lifespan)

app.include_router(scan.router)
app.include_router(health.router)
app.include_router(wines.router)
app.include_router(curate.router)
