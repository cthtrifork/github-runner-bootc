#!/usr/bin/env bash
# The runner image is declared twice: github-runner.image (read by bootc to bind it) and github-runner@.container (read by
# podman to run it). Both must be the same digest-pinned reference, or the unit would run an image that is not bound.
set -euo pipefail

dir="${1:-system_files/usr/share/containers/systemd}"
image_ref="$(sed -n 's/^Image=//p' "$dir/github-runner.image")"
unit_ref="$(sed -n 's/^Image=//p' "$dir/github-runner@.container")"

[[ -n "$image_ref" ]] || { echo "no Image= in github-runner.image" >&2; exit 1; }
[[ "$image_ref" == "$unit_ref" ]] || { echo "Image= differs: image='$image_ref' unit='$unit_ref'" >&2; exit 1; }
[[ "$image_ref" == *@sha256:* ]] || { echo "Image= is not pinned by digest: $image_ref" >&2; exit 1; }
grep -qx 'Pull=never' "$dir/github-runner@.container" || { echo "unit must set Pull=never" >&2; exit 1; }
bound=/usr/lib/bootc/bound-images.d/github-runner.image
grep -q "ln -s /usr/share/containers/systemd/github-runner.image $bound" github-runner.containerfile \
    || { echo "containerfile does not link the image into bound-images.d" >&2; exit 1; }
echo "ok: $image_ref"
