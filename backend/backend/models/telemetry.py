"""Client-reported scan telemetry (opt-in "Send Diagnostics?" on iOS).

The iOS client POSTs one of these at the conclusion of a scan — success,
cancelled, or error. Captures the device-side timing the server can't see
(DNS/TCP/upload/wait/ttfb) alongside the pipeline phases, keyed by scan_id so
it joins to ScanLog and (when SAVE_SCAN_IMAGES is on) the saved scan photo.
"""

from typing import Literal

from pydantic import BaseModel

ScanOutcome = Literal["completed", "cancelled", "error", "interrupted"]


class TimelineEntry(BaseModel):
    label: str
    ms: int


class ScanTelemetry(BaseModel):
    scan_id: str
    outcome: ScanOutcome = "completed"

    # Client / device metadata
    app_version: str | None = None
    git_sha: str | None = None
    device_model: str | None = None
    os_version: str | None = None
    network_type: str | None = None  # wifi | cellular | unknown
    backend_url: str | None = None

    # Upload characteristics
    upload_bytes: int | None = None
    orig_width: int | None = None
    orig_height: int | None = None
    sent_width: int | None = None
    sent_height: int | None = None
    upload_max_side: int | None = None
    upload_jpeg_quality: float | None = None

    # Network phases (URLSessionTaskTransactionMetrics)
    dns_ms: int | None = None
    tcp_ms: int | None = None
    request_ms: int | None = None
    response_ms: int | None = None
    wait_ms: int | None = None
    ttfb_ms: int | None = None
    http_ok_ms: int | None = None

    # Pipeline phases (from the complete event)
    receive_ms: int | None = None
    first_wine_ms: int | None = None
    ollama_ms: int | None = None
    image_ms: int | None = None
    brave_search_ms: int | None = None
    image_download_ms: int | None = None
    sommelier_ms: int | None = None
    total_ms: int | None = None

    # Counts
    wine_count: int | None = None
    cache_hits: int | None = None
    parse_errors: int | None = None

    event_timeline: list[TimelineEntry] = []
