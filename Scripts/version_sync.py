#!/usr/bin/env python3
"""Single source of truth for the project version across every client.

The repo carries the version in seven places that must agree:

  - VERSION                      4-part  MAJOR.MINOR.PATCH.MICRO  (canonical)
  - backend/pyproject.toml       3-part  (semver — packaging metadata)
  - backend/uv.lock              3-part  (uv records the project's own version)
  - web/package.json             4-part  (npm metadata)
  - web/package-lock.json        4-part  (root + packages[""], npm lock metadata)
  - ios/project.yml              3-part  MARKETING_VERSION -> CFBundleShortVersionString
                                 (iOS About screen, DebugHUD, scan telemetry app_version)
  - README.md                    4-part  "Latest release" badge

`VERSION` is the source of truth. The backend already reads it at runtime
(backend/config.py -> APP_VERSION -> /health), but the other six are static
copies that drift unless a bump propagates to all of them. This script does the
propagation (`set`) and the invariant check (`check`, run in CI).

Stdlib only — CI runs it with a bare python3, no install step.

Usage:
  python3 Scripts/version_sync.py check            # assert all seven agree
  python3 Scripts/version_sync.py set 0.3.3.0      # write all seven from one arg
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FOUR_PART = re.compile(r"^\d+\.\d+\.\d+\.\d+$")


def _three(four: str) -> str:
    """Drop the MICRO component: 0.3.3.0 -> 0.3.3 (semver surfaces)."""
    return ".".join(four.split(".")[:3])


class Location:
    """One version store: how to read its current value and rewrite it."""

    def __init__(self, path: str, pattern: str, kind: str, label: str):
        self.path = ROOT / path
        self.rel = path
        # pattern has exactly three groups: (prefix)(value)(suffix).
        self.pattern = re.compile(pattern, re.MULTILINE)
        self.kind = kind  # "four" or "three"
        self.label = label

    def expected(self, four: str) -> str:
        return four if self.kind == "four" else _three(four)

    def current(self) -> list[str]:
        """Every project-version value in the file (a store may hold several,
        e.g. the lockfile's root + packages[""] entries)."""
        text = self.path.read_text("utf-8")
        vals = [m.group(2) for m in self.pattern.finditer(text)]
        if not vals:
            raise SystemExit(f"version_sync: no version match in {self.rel}")
        return vals

    def write(self, four: str) -> bool:
        text = self.path.read_text("utf-8")
        want = self.expected(four)
        # count=0: rewrite every project-version occurrence in the file. The
        # patterns are anchored so they never match a dependency's version.
        new = self.pattern.sub(lambda m: f"{m.group(1)}{want}{m.group(3)}", text)
        if new == text:
            return False
        self.path.write_text(new, "utf-8")
        return True


# VERSION is handled directly (whole-file), not via a Location regex.
LOCATIONS = [
    Location(
        "backend/pyproject.toml",
        r'^(version = ")([^"]+)(")',
        "three",
        "pyproject.toml",
    ),
    Location(
        # Anchored to the project package stanza so no dependency is touched.
        # uv self-heals this on `uv sync`, but the guard keeps the commit honest.
        "backend/uv.lock",
        r'(name = "visual-winelist-backend"\nversion = ")([^"]+)(")',
        "three",
        "uv.lock",
    ),
    Location(
        "web/package.json",
        r'^(  "version": ")([^"]+)(")',
        "four",
        "package.json",
    ),
    Location(
        # Both the root and packages[""] entries — anchored to the curator's own
        # "name" so dependency versions are never touched. Matches twice.
        "web/package-lock.json",
        r'("name": "visual-winelist-curator",\n\s*"version": ")([^"]+)(")',
        "four",
        "package-lock.json",
    ),
    Location(
        "ios/project.yml",
        r'(MARKETING_VERSION: ")([^"]+)(")',
        "three",
        "ios MARKETING_VERSION",
    ),
    Location(
        "README.md",
        r"(release-v)([0-9][0-9.]*)(-blue)",
        "four",
        "README badge",
    ),
]


def read_version_file() -> str:
    return (ROOT / "VERSION").read_text("utf-8").strip()


def cmd_check() -> int:
    four = read_version_file()
    if not FOUR_PART.match(four):
        print(f"VERSION '{four}' is not 4-part MAJOR.MINOR.PATCH.MICRO", file=sys.stderr)
        return 1

    rows = [("VERSION (source of truth)", four, four, True)]
    ok = True
    for loc in LOCATIONS:
        vals = loc.current()
        want = loc.expected(four)
        match = set(vals) == {want}
        ok = ok and match
        cur = vals[0] if len(set(vals)) == 1 else "/".join(vals)
        rows.append((loc.label, cur, want, match))

    width = max(len(r[0]) for r in rows)
    print(f"Version sync check against VERSION = {four}\n")
    for label, cur, want, match in rows:
        mark = "ok " if match else "BAD"
        detail = cur if match else f"{cur}  (expected {want})"
        print(f"  [{mark}] {label.ljust(width)}  {detail}")

    if not ok:
        print(
            f"\nVersion drift detected. Run: python3 Scripts/version_sync.py set {four}",
            file=sys.stderr,
        )
        return 1
    print("\nAll version stores agree.")
    return 0


def cmd_set(four: str) -> int:
    if not FOUR_PART.match(four):
        print(
            f"version '{four}' must be 4-part MAJOR.MINOR.PATCH.MICRO (e.g. 0.3.3.0)",
            file=sys.stderr,
        )
        return 2

    version_file = ROOT / "VERSION"
    if version_file.read_text("utf-8").strip() != four:
        version_file.write_text(f"{four}\n", "utf-8")  # preserve trailing newline
        print(f"  VERSION -> {four}")

    for loc in LOCATIONS:
        want = loc.expected(four)
        if loc.write(four):
            print(f"  {loc.rel} -> {want}")

    print()
    return cmd_check()


def main(argv: list[str]) -> int:
    if len(argv) >= 1 and argv[0] == "check":
        return cmd_check()
    if len(argv) == 2 and argv[0] == "set":
        return cmd_set(argv[1])
    print(__doc__)
    print("error: expected 'check' or 'set <X.Y.Z.W>'", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
