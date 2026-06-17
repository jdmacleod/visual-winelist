import os
import warnings
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from backend import config
from backend.db.session import init_db
from backend.routers import curate, health, scan, wines


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    os.makedirs(config.IMAGE_CACHE_DIR, exist_ok=True)
    await init_db()

    if not config.BRAVE_API_KEY:
        warnings.warn("BRAVE_API_KEY not set — image search will be skipped", stacklevel=2)

    yield


app = FastAPI(title="visual-winelist backend", version="0.2.0", lifespan=lifespan)

app.include_router(scan.router)
app.include_router(health.router)
app.include_router(wines.router)
app.include_router(curate.router)
