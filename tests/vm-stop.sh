#!/usr/bin/env bash
# Save the VM journal as out/journal/<name>.log and power QEMU off: tests/vm-stop.sh offline
set -uo pipefail

name="${1:?Usage: $0 <name>}"
mkdir -p out/journal
"$(dirname "$0")/vm-ssh.sh" 'journalctl -b --no-pager -o short-precise' >"out/journal/${name}.log" || true
# a clean shutdown: the loaded runner image is several GiB that must reach the disk before the next boot
"$(dirname "$0")/vm-ssh.sh" 'sync; systemctl poweroff' || true
for _ in $(seq 1 60); do
    pgrep -x qemu-system-x86 >/dev/null || exit 0
    sleep 1
done
echo quit | sudo socat - unix-connect:/tmp/qemu-monitor-sock || true
sleep 3
