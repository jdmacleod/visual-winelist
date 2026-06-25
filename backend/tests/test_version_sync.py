"""Regression guard: every version store in the repo must agree with VERSION.

This fails loudly if a release bumps VERSION but forgets to propagate to
pyproject.toml, uv.lock, package.json, package-lock.json, ios MARKETING_VERSION,
or the README badge — the drift that left iOS reporting 0.2.12 for 11 releases.
Run the fix with: python3 Scripts/version_sync.py set <X.Y.Z.W>.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "Scripts" / "version_sync.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("version_sync", SCRIPT)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_all_version_stores_agree() -> None:
    """The live invariant — drift makes this fail with a readable table."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "check"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"version drift detected:\n{result.stdout}\n{result.stderr}"


def test_three_part_drops_micro() -> None:
    mod = _load_module()
    assert mod._three("0.3.3.0") == "0.3.3"
    assert mod._three("1.2.3.4") == "1.2.3"


def test_four_part_format() -> None:
    mod = _load_module()
    assert mod.FOUR_PART.match("0.3.3.0")
    assert not mod.FOUR_PART.match("0.3.3")
    assert not mod.FOUR_PART.match("0.3.3.0-rc1")
    assert not mod.FOUR_PART.match("v0.3.3.0")


def test_location_write_rewrites_every_occurrence(tmp_path: Path) -> None:
    """The write engine: a store with two version lines (like the lockfile) gets
    both rewritten, and the 3-part 'kind' drops MICRO."""
    mod = _load_module()
    target = tmp_path / "fake.json"
    target.write_text('"version": "0.1.0"\n... "version": "0.1.0"\n', "utf-8")
    # Absolute path wins over ROOT in `ROOT / path`, so this points at tmp.
    loc = mod.Location(str(target), r'("version": ")([^"]+)(")', "three", "fake")

    assert loc.current() == ["0.1.0", "0.1.0"]
    assert loc.write("0.3.4.0") is True
    # 3-part, both occurrences updated (current() returns every match).
    assert loc.current() == ["0.3.4", "0.3.4"]
    assert loc.write("0.3.4.0") is False  # idempotent: no change, returns False


def test_set_rejects_non_four_part_version() -> None:
    mod = _load_module()
    assert mod.cmd_set("0.3.3") == 2  # 3-part rejected
    assert mod.cmd_set("v0.3.3.0") == 2  # v-prefix rejected
    assert mod.main(["set", "0.3.3"]) == 2


def test_main_dispatch_rejects_bad_args() -> None:
    mod = _load_module()
    assert mod.main([]) == 2
    assert mod.main(["bogus"]) == 2
