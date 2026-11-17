#!/usr/bin/env bash
# Runs inside the booted image, with no credentials seeded.
set -eo pipefail
trap 'echo "💥 Error on line $LINENO (exit $?): last cmd: $BASH_COMMAND"' ERR

echo "== System testing (github-runner-bootc) =="
id

echo "--- tools ---"
for c in podman skopeo xfs_quota jq curl openssl bootc github-runner-seed-app; do
    command -v "$c" >/dev/null || { echo "missing: $c"; exit 1; }
done
for f in mint-jitconfig prepare-instance update-and-drain prune; do
    test -x "/usr/libexec/github-runner/$f" || { echo "missing or not executable: $f"; exit 1; }
done

echo "--- units ---"
systemctl cat 'github-runner@.service' >/dev/null
systemctl is-enabled --quiet github-runner-update.timer
systemctl is-enabled --quiet github-runner-prune.timer
[ "$(systemctl is-enabled bootc-fetch-apply-updates.timer 2>/dev/null || true)" = "masked" ]
if systemctl is-active --quiet 'github-runner@1.service'; then
    echo "github-runner@1 is running but nothing was seeded"
    exit 1
fi

echo "--- runner image ---"
ref="$(sed -n 's/^Image=//p' '/usr/share/containers/systemd/github-runner@.container')"
echo "runner image: $ref"
if [ -e /usr/share/github-runner/offline ]; then
    echo "variant: offline"
    test -d /usr/share/github-runner/runner-image
else
    echo "variant: default"
fi
grep -qx 'Pull=never' '/usr/share/containers/systemd/github-runner@.container'
systemctl is-enabled --quiet github-runner-image-load.service
systemctl start github-runner-image-load.service
podman image exists "$ref" || {
    echo "the runner image was not loaded into the container storage"
    journalctl -u github-runner-image-load.service --no-pager | tail -20
    exit 1
}

echo "--- the generated unit never pulls ---"
unit="$(systemctl cat 'github-runner@1.service')"
grep -q -- '--pull=never\|--pull never' <<<"$unit" || { echo "generated unit does not pass --pull=never"; echo "$unit"; exit 1; }

echo "--- the container starts from the local storage with the registry unreachable ---"
# no JIT config: it must fail on that, not on a pull
out="$(podman run --rm --pull=never --user 1001 "$ref" /home/runner/run.sh 2>&1 || true)"
echo "$out" | head -20
if grep -qiE 'unable to pull|pinging container registry|no such host|lookup .* on|dial tcp' <<<"$out"; then
    echo "the runner tried to use the network"
    exit 1
fi

echo "--- disk usage (MiB) ---"
df -BM --output=target,used,avail / /var | cat
graphroot="$(podman info --format '{{.Store.GraphRoot}}')"
echo "container storage: $graphroot"
du -xsm /sysroot/ostree/repo /sysroot/ostree/deploy "$graphroot" /var/lib/github-runner /usr/share/github-runner 2>&1 || true
podman system df

echo "== OK =="
