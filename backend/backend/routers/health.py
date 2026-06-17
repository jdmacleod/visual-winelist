from fastapi import APIRouter

from backend import config
from backend.services import ollama_client

router = APIRouter()


@router.get("/health")
async def health() -> dict:
    ollama_ok = await ollama_client.check_reachable()
    brave_ok = bool(config.BRAVE_API_KEY)
    status = "ok" if (ollama_ok and brave_ok) else "degraded"
    return {"status": status, "ollama": ollama_ok, "brave_key": brave_ok}
