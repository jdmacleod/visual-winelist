#!/usr/bin/env python3
"""Aggregate iOS line coverage from an xccov JSON report and enforce a floor.

Reads `xcrun xccov view --report --json` output on stdin. Keeps files whose path
matches the include regex and does not match the exclude regex, sums their
executable/covered lines, and fails (exit 1) if the pooled line coverage is below
the minimum. See Scripts/ios-coverage-gate.sh for the rationale (E16).
"""

import json
import re
import sys


def main() -> int:
    min_pct = float(sys.argv[1])
    include = re.compile(sys.argv[2])
    exclude = re.compile(sys.argv[3])

    report = json.load(sys.stdin)

    covered = 0
    executable = 0
    kept: list[tuple[str, int, int]] = []
    for target in report.get("targets", []):
        for f in target.get("files", []):
            path = f.get("path", f.get("name", ""))
            if not include.search(path) or exclude.search(path):
                continue
            ex = int(f.get("executableLines", 0))
            cov = int(f.get("coveredLines", 0))
            executable += ex
            covered += cov
            kept.append((path, cov, ex))

    if executable == 0:
        print("iOS coverage gate: no gated files matched — check the include regex.")
        return 1

    pct = 100.0 * covered / executable
    kept.sort(key=lambda r: (r[2] and r[1] / r[2]))

    print(f"{'='*72}")
    print(f"iOS coverage gate — logic core ({len(kept)} files)")
    print(f"{'='*72}")
    for path, cov, ex in kept:
        short = path.split("/Sources/VisualWinelistIOS/", 1)[-1]
        fpct = (100.0 * cov / ex) if ex else 100.0
        print(f"  {fpct:5.1f}%  {cov:>4}/{ex:<4}  {short}")
    print(f"{'-'*72}")
    print(f"  POOLED: {pct:.1f}%  ({covered}/{executable} lines)  floor={min_pct:.0f}%")
    print(f"{'='*72}")

    if pct + 1e-9 < min_pct:
        print(f"FAIL: line coverage {pct:.1f}% is below the {min_pct:.0f}% floor.")
        return 1
    print(f"PASS: line coverage {pct:.1f}% meets the {min_pct:.0f}% floor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
