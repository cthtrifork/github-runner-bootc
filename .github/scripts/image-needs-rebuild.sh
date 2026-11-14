#!/usr/bin/env bash
# Writes build=true|false to $GITHUB_OUTPUT.
# - push: outputs the commit each published image was built from (its org.opencontainers.image.revision label); the
#   workflow builds when the image files changed since either, so a cancelled build is retried by the next push.
# - schedule: rebuilds when the base image is newer than the published image or the published image is 14 days old.
# - anything else (pull request, manual run): builds; the workflow narrows a pull request by the files it changed.
set -euo pipefail

if [[ "$EVENT_NAME" == push ]]; then
    revision() { # <image ref>: the commit the published image was built from, empty if there is none
        skopeo inspect --override-os linux --override-arch amd64 --creds "$ACTOR:$TOKEN" "docker://$1:latest" \
            --format '{{index .Labels "org.opencontainers.image.revision"}}' 2>/dev/null || true
    }
    default_rev="$(revision "$IMAGE")"
    offline_rev="$(revision "$OFFLINE_IMAGE")"
    if [[ -z "$default_rev" || -z "$offline_rev" ]]; then
        echo "A published image has no revision: build"
        echo "build=true" >>"$GITHUB_OUTPUT"
    else
        {
            echo "build=false"
            echo "default_rev=$default_rev"
            echo "offline_rev=$offline_rev"
        } >>"$GITHUB_OUTPUT"
    fi
    exit 0
fi

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
