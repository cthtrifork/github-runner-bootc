#!/usr/bin/env bash
# Writes version=<runner version>-<YYYYMMDD>.<iteration> and runner_version=<runner version> to $GITHUB_OUTPUT.
# The runner version is the leading X.Y.Z of RUNNER_IMAGE_TAG in the Containerfile (the GitHub Actions runner inside the
# runner image). The date is UTC. The iteration is one above the highest iteration already published under the same
# runner version and date, in either image, so both variants get the same tag and a second build the same day gets a new one.
set -euo pipefail

runner_tag="$(sed -n 's/^ARG RUNNER_IMAGE_TAG=\([^ ]*\).*/\1/p' github-runner.containerfile)"
runner_version="${runner_tag#v}"
runner_version="${runner_version%%-*}"
[[ "$runner_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::no runner version in RUNNER_IMAGE_TAG '$runner_tag'"; exit 1; }

day="$(date -u +%Y%m%d)"
prefix="${runner_version//./\\.}-$day"
iteration=0
for image in "$IMAGE" "$OFFLINE_IMAGE"; do
    tags="$(skopeo list-tags --creds "$ACTOR:$TOKEN" "docker://$image" 2>/dev/null | jq -r '.Tags[]' || true)"
    last="$(grep -E "^$prefix\.[0-9]+$" <<<"$tags" | sed 's/.*\.//' | sort -n | tail -n1 || true)"
    if [[ -n "$last" && "$last" -gt "$iteration" ]]; then iteration="$last"; fi
done

version="$runner_version-$day.$((iteration + 1))"
echo "Release version: $version"
{
    echo "version=$version"
    echo "runner_version=$runner_version"
} >>"$GITHUB_OUTPUT"
