#!/usr/bin/env bash
# Runs inside the booted image (QEMU in CI, or on a real host). With no credentials seeded and, in the airgap e2e, no
# network at all: everything here must hold offline.
set -eo pipefail
trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (github-runner-bootc) =="
id

echo "--- tools ---"
for c in podman skopeo jq curl openssl bootc github-runner-seed-app; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done
for f in mint-jitconfig prepare-instance update-and-drain prune; do
    test -x "/usr/libexec/github-runner/$f" || { echo "missing or not executable: $f"; exit 1; }
done

echo "--- units ---"
systemctl cat 'github-runner@.service' >/dev/null
systemctl is-enabled --quiet github-runner-update.timer
systemctl is-enabled --quiet github-runner-prune.timer
# the stock timer reboots mid-job; ours drains first
[ "$(systemctl is-enabled bootc-fetch-apply-updates.timer 2>/dev/null || true)" = "masked" ]
# idle until the GitHub App is seeded
if systemctl is-active --quiet 'github-runner@1.service'; then
    echo "github-runner@1 is running but nothing was seeded"
    exit 1
fi

echo "--- bound runner image (works without a registry) ---"
ref="$(sed -n 's/^Image=//p' /usr/share/containers/systemd/github-runner.image)"
echo "bound image: $ref"
test -L /usr/lib/bootc/bound-images.d/github-runner.image
[ "$(sed -n 's/^Image=//p' '/usr/share/containers/systemd/github-runner@.container')" = "$ref" ]
grep -qx 'Pull=never' '/usr/share/containers/systemd/github-runner@.container'
podman --storage-opt=additionalimagestore=/usr/lib/bootc/storage image exists "$ref" || {
    echo "the runner image is not in the bootc bound store: the disk image was built without it"
    bootc image list 2>&1 || true
    exit 1
}

echo "--- the generated unit never pulls ---"
unit="$(systemctl cat 'github-runner@1.service')"
grep -q -- '--pull=never\|--pull never' <<<"$unit" || { echo "generated unit does not pass --pull=never"; echo "$unit"; exit 1; }
grep -q 'additionalimagestore=/usr/lib/bootc/storage' <<<"$unit"

echo "--- the container starts from the bound store with the registry unreachable ---"
# Run the image's own entrypoint with no JIT config: it must start and fail on the missing config, not on a pull.
out="$(podman --storage-opt=additionalimagestore=/usr/lib/bootc/storage run --rm --pull=never --user 1001 \
    "$ref" /home/runner/run.sh 2>&1 || true)"
echo "$out" | head -20
if grep -qiE 'unable to pull|pinging container registry|no such host|lookup .* on|dial tcp' <<<"$out"; then
    echo "the runner tried to use the network"
    exit 1
fi

echo "== OK =="
