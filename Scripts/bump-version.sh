#!/usr/bin/env bash
# Bump the project version everywhere from a single 4-part argument.
#
# VERSION is the source of truth; this propagates it to backend/pyproject.toml,
# backend/uv.lock, web/package.json, web/package-lock.json, ios/project.yml
# (MARKETING_VERSION), and the README badge, then verifies they all agree.
# CHANGELOG.md is yours to edit separately.
#
# Usage: ./Scripts/bump-version.sh 0.3.4.0
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <MAJOR.MINOR.PATCH.MICRO>   e.g. $0 0.3.4.0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/version_sync.py" set "$1"
