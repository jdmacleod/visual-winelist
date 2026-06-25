#!/usr/bin/env bash
# iOS line-coverage gate (E16).
#
# E15 deleted the macOS mirror and with it the old root `swift test` 70% gate.
# That gate measured the mirror's shared-logic subset; the iOS tree's *whole*
# coverage is much lower because it carries UI (Views/Design), device (Camera),
# and debug/telemetry code the XCTest suite can't unit-test. Rather than gate the
# whole tree at a meaningless low number, this gate recalibrates the exclusion set
# to the **logic core the suite actually exercises** (Backend, Models, ViewModels)
# and enforces a floor against that — a regression ratchet, not an aspiration.
#
# Usage: ios-coverage-gate.sh <TestResults.xcresult> [min_percent]
#   min_percent defaults to $IOS_COVERAGE_MIN or the value below.
set -euo pipefail

# Floor is set just under the measured logic-core coverage at the time of E16
# (52.1% pooled across Backend/Models/ViewModels/StartupValidator). It's a
# regression ratchet: raise it as the suite grows (WineListViewModel is the main
# gap at ~15%), but never let coverage silently fall below this.
RESULT_BUNDLE="${1:?usage: ios-coverage-gate.sh <result.xcresult> [min_percent]}"
MIN="${2:-${IOS_COVERAGE_MIN:-50}}"

# Files/dirs excluded from the gate: UI, device-bound, generated, and debug code
# that unit tests cannot meaningfully cover. Everything else under the app target
# (Backend/, Models/, ViewModels/, ...) is the gated logic core.
EXCLUDE_REGEX='/(Views|Design|Debug|Camera|Generated|Resources)/|VisualWinelistIOSApp\.swift|ScanTelemetryReporter\.swift|/DebugBridge'

# Only gate the app target's own sources; ignore test targets and the
# DebugBridge* modules (which appear as separate targets in the report).
INCLUDE_REGEX='/Sources/VisualWinelistIOS/'

xcrun xccov view --report --json "$RESULT_BUNDLE" \
  | python3 "$(dirname "$0")/ios_coverage_gate.py" "$MIN" "$INCLUDE_REGEX" "$EXCLUDE_REGEX"
