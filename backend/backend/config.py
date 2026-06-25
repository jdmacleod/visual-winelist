import os
from pathlib import Path

_VERSION_FILE = Path(__file__).parents[2] / "VERSION"
try:
    APP_VERSION: str = _VERSION_FILE.read_text("utf-8").strip() or "0.0.0"
except OSError:
    APP_VERSION = "0.0.0"

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


def _bool_env(name: str, default: str) -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


# Accept opt-in scan telemetry from the iOS client at POST /telemetry/scan.
TELEMETRY_ENABLED: bool = _bool_env("TELEMETRY_ENABLED", "true")
# Persist the uploaded scan photo to scans/{scan_id}.jpg for content inspection.
# Off by default — it stores raw photos. Correlates to telemetry + ScanLog by scan_id.
SAVE_SCAN_IMAGES: bool = _bool_env("SAVE_SCAN_IMAGES", "false")
# Default kept-photo count when saving is on but no per-request retention is given
# (e.g. the SAVE_SCAN_IMAGES env path, or a client that omits the header). Bounds
# disk growth so "save" never means "save forever". 0 disables pruning.
SCAN_IMAGE_RETENTION_DEFAULT: int = int(os.environ.get("SCAN_IMAGE_RETENTION_DEFAULT", "50"))

# Image variant dimensions (px, longest side) — tune via env vars for experiments.
IMAGE_THUMB_WIDTH: int = int(os.environ.get("IMAGE_THUMB_WIDTH", "120"))
IMAGE_CARD_WIDTH: int = int(os.environ.get("IMAGE_CARD_WIDTH", "320"))
IMAGE_DETAIL_WIDTH: int = int(os.environ.get("IMAGE_DETAIL_WIDTH", "800"))
IMAGE_WEBP_QUALITY: int = int(os.environ.get("IMAGE_WEBP_QUALITY", "80"))
