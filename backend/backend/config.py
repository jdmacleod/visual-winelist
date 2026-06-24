import os
from pathlib import Path

_VERSION_FILE = Path(__file__).parents[2] / "VERSION"
APP_VERSION: str = _VERSION_FILE.read_text().strip() if _VERSION_FILE.exists() else "0.0.0"

BRAVE_API_KEY: str = os.environ.get("BRAVE_API_KEY", "")
OLLAMA_BASE_URL: str = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
IMAGE_CACHE_DIR: str = os.environ.get(
    "IMAGE_CACHE_DIR",
    os.path.expanduser("~/.visual-winelist/image-cache/"),
)
DATABASE_URL: str = os.environ.get(
    "DATABASE_URL",
    f"sqlite+aiosqlite:///{os.path.expanduser('~/.visual-winelist/cache.db')}",
)
MAX_UPLOAD_SIZE: int = int(os.environ.get("MAX_UPLOAD_SIZE", str(25 * 1024 * 1024)))

# Image variant dimensions (px, longest side) — tune via env vars for experiments.
IMAGE_THUMB_WIDTH: int = int(os.environ.get("IMAGE_THUMB_WIDTH", "120"))
IMAGE_CARD_WIDTH: int = int(os.environ.get("IMAGE_CARD_WIDTH", "320"))
IMAGE_DETAIL_WIDTH: int = int(os.environ.get("IMAGE_DETAIL_WIDTH", "800"))
IMAGE_WEBP_QUALITY: int = int(os.environ.get("IMAGE_WEBP_QUALITY", "80"))
