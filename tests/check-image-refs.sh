#!/usr/bin/env bash
# The runner image tag is in github-runner.containerfile and in the Quadlet unit; they must match.
set -euo pipefail

unit="${1:-system_files/usr/share/containers/systemd/github-runner@.container}"
containerfile="${2:-github-runner.containerfile}"

ref="$(sed -n 's/^Image=//p' "$unit")"
repo="$(sed -n 's/^ARG RUNNER_IMAGE=//p' "$containerfile")"
tag="$(sed -n 's/^ARG RUNNER_IMAGE_TAG=\([^ ]*\).*/\1/p' "$containerfile")"

[[ -n "$ref" && -n "$repo" && -n "$tag" ]] || { echo "could not read the image from $unit and $containerfile" >&2; exit 1; }
[[ "$ref" == "${repo}:${tag}" ]] || { echo "Image= is '$ref' but the containerfile embeds '${repo}:${tag}'" >&2; exit 1; }
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "the tag must be an exact version like v1.2.3: $tag" >&2; exit 1; }
grep -qx 'Pull=never' "$unit" || { echo "the unit must set Pull=never" >&2; exit 1; }
echo "ok: $ref"
