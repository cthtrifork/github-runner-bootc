#!/usr/bin/env bash
set -euo pipefail

script=".github/scripts/image-needs-rebuild.sh"
now="$(date -u -d '2026-01-15T00:00:00Z' +%s)"

assert_rebuild() {
  if ! "$script" "$@"; then
    echo "expected a rebuild for: $*" >&2
    exit 1
  fi
}

assert_skip() {
  if "$script" "$@"; then
    echo "expected no rebuild for: $*" >&2
    exit 1
  fi
}

assert_rebuild '2026-01-11T00:00:00Z' '2026-01-10T00:00:00Z' "$now"
assert_rebuild '2025-12-31T00:00:00Z' '2026-01-01T00:00:00Z' "$now"
assert_skip '2026-01-01T00:00:00Z' '2026-01-01T00:00:01Z' "$now"
assert_skip '2026-01-01T00:00:00Z' '2026-01-02T00:00:00Z' "$now"
assert_skip '2026-01-01T00:00:00Z' '2026-01-02T00:00:01Z' "$now"

echo "ok: image freshness decisions"
