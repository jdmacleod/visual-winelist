import os

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
