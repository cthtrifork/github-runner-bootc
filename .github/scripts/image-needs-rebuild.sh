#!/usr/bin/env bash
# Writes build=true|false to $GITHUB_OUTPUT. Only the scheduled run can say false: it rebuilds when the base image is
# newer than the published image or the published image is 14 days old.
set -euo pipefail

if [[ "$EVENT_NAME" != schedule ]]; then
    echo "build=true" >>"$GITHUB_OUTPUT"
    exit 0
fi

created() { # <image ref> [credentials]: creation time of the linux/amd64 image, in epoch seconds
    skopeo inspect --override-os linux --override-arch amd64 ${2:+--creds "$2"} "docker://$1" --format '{{.Created.Unix}}'
}

base_image="$(awk '$1 == "FROM" { print $2; exit }' github-runner.containerfile)"
base_epoch="$(created "$base_image")"
published_epoch="$(created "$IMAGE:latest" "$ACTOR:$TOKEN" 2>/dev/null || true)"

if [[ -z "$published_epoch" ]]; then
    echo "No published image yet: build"
    echo "build=true" >>"$GITHUB_OUTPUT"
    exit 0
fi

if ((base_epoch > published_epoch || $(date -u +%s) - published_epoch >= 14 * 86400)); then
    echo "The base image is newer or the published image is 14 days old: build"
    echo "build=true" >>"$GITHUB_OUTPUT"
else
    echo "The published image is up to date: skip the build and the release"
    echo "build=false" >>"$GITHUB_OUTPUT"
fi
