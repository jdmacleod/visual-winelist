# TODOS

Deferred items from the v2 implementation and design reviews.

## E2: Personal scan history

Save each scan with restaurant name + date. Requires user tagging UI at scan time.

---

## E3: Personal wine cellar

Mark wines tried/want-to-try. Requires user identity model not present in v2.

---

## E5: Purchase links

Vivino + Wine.com deep links per wine detail view.

---

## E6: Card sharing

Share wine card via iOS share sheet / AirDrop.

---

## Security: CI gitleaks full-history scan

The pre-commit hook blocks new secrets in local commits but can be bypassed with
`--no-verify` or a direct GitHub web/API push. Add a `gitleaks detect --source .`
job to `.github/workflows/ci.yml` that scans full history on every PR.

---

## SSE: lineBuffer memory cap in BackendClient.swift

The byte-iteration loop in `BackendClient.scan()` accumulates bytes in `lineBuffer`
with no capacity limit. A misbehaving backend or misconfigured proxy flushing a
multi-MB response as a single line would cause unbounded `Data` growth until OOM
or connection close. Fix: add a hard cap (e.g. 1 MB) that discards oversized
pseudo-lines and continues.

---

## SSE: iOS UTF-8 chunk boundary issue in IOSScanSession.swift

`didReceive data:` decodes the full `Data` chunk to `String` before line
splitting. If a URLSession delivery boundary falls mid-multibyte character (e.g.
an accented wine name), the entire chunk is silently dropped — potentially
several complete SSE events. Fix: accumulate raw `Data` in `lineBuffer` and
decode per-line after splitting on `0x0A`, matching `BackendClient.swift`.

---

## Security: Pin Docker base image digests

`FROM python:3.13-slim` and `COPY --from=ghcr.io/astral-sh/uv:latest` are floating
tags. Pin both to specific SHA256 digests (or a semver for uv) for reproducible,
supply-chain-safe builds.

---
