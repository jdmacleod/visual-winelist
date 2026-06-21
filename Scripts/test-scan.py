#!/usr/bin/env python3
"""
Diagnostic script — tests the /scan SSE endpoint directly.
Usage:
  cd /path/to/visual-winelist
  uv run python scripts/test-scan.py [image_path] [backend_url]

Defaults:
  image_path  = resources/images/dueamici.jpg
  backend_url = http://localhost:8000
"""

import sys
import time
import urllib.request
import urllib.parse
import json
import uuid
import os

IMAGE = sys.argv[1] if len(sys.argv) > 1 else "resources/images/dueamici.jpg"
BACKEND = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:8000"


def check_health():
    try:
        with urllib.request.urlopen(f"{BACKEND}/health", timeout=5) as r:
            data = json.loads(r.read())
            print(f"[health] {data}")
            return data
    except Exception as e:
        print(f"[health] FAILED: {e}")
        sys.exit(1)


def scan(image_path: str):
    with open(image_path, "rb") as f:
        image_data = f.read()

    magic = " ".join(f"{b:02X}" for b in image_data[:4])
    print(f"[scan] image: {len(image_data)} bytes, magic={magic}, path={image_path}")

    boundary = uuid.uuid4().hex
    body_parts = [
        f"--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="image"; filename="scan.jpg"\r\n'.encode(),
        b"Content-Type: image/jpeg\r\n\r\n",
        image_data,
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    body = b"".join(body_parts)

    req = urllib.request.Request(
        f"{BACKEND}/scan",
        data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        method="POST",
    )

    wine_count = 0
    error_count = 0
    t0 = time.time()

    with urllib.request.urlopen(req, timeout=180) as resp:
        print(f"[scan] HTTP {resp.status}, content-type={resp.headers.get('Content-Type')}")
        event_type = None
        for raw_line in resp:
            line = raw_line.decode("utf-8", errors="replace").rstrip("\r\n")
            if line.startswith("event: "):
                event_type = line[7:]
            elif line.startswith("data: "):
                data_str = line[6:]
                elapsed = time.time() - t0
                if event_type == "wine":
                    wine = json.loads(data_str)
                    wine_count += 1
                    print(f"  [{elapsed:.1f}s] wine #{wine_count}: {wine['name']!r}")
                elif event_type == "error":
                    err = json.loads(data_str)
                    error_count += 1
                    print(f"  [{elapsed:.1f}s] ERROR: code={err['code']!r}, msg={err['message']!r}")
                elif event_type == "complete":
                    result = json.loads(data_str)
                    print(f"  [{elapsed:.1f}s] COMPLETE: {result}")
            elif not line:
                event_type = None

    print(f"\n[scan] done in {time.time()-t0:.1f}s: {wine_count} wines, {error_count} errors")
    if wine_count == 0:
        print("\n⚠  No wines extracted — check backend logs for errors.")
    else:
        print(f"\n✓  Extraction working.")


if __name__ == "__main__":
    health = check_health()
    if not health.get("ollama"):
        print("⚠  Ollama not connected — run: ollama serve")
        sys.exit(1)
    scan(IMAGE)
