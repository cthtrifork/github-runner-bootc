#!/usr/bin/env bash
# The runner image of the Quadlet unit is embedded in the offline image and loaded by tag: it needs an exact version tag
# and Pull=never.
set -euo pipefail

unit="${1:-system_files/usr/share/containers/systemd/github-runner@.container}"

ref="$(sed -n 's/^Image=//p' "$unit")"
[[ -n "$ref" ]] || { echo "no Image= in $unit" >&2; exit 1; }
[[ "${ref##*:}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "the tag must be an exact version like v1.2.3: $ref" >&2; exit 1; }
grep -qx 'Pull=never' "$unit" || { echo "the unit must set Pull=never" >&2; exit 1; }
echo "ok: $ref"
