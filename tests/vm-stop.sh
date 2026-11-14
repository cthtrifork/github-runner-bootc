#!/usr/bin/env bash
# Save the VM journal as out/journal/<name>.log and power QEMU off: tests/vm-stop.sh offline
set -uo pipefail

name="${1:?Usage: $0 <name>}"
mkdir -p out/journal
"$(dirname "$0")/vm-ssh.sh" 'journalctl -b --no-pager -o short-precise' >"out/journal/${name}.log" || true
echo quit | sudo socat - unix-connect:/tmp/qemu-monitor-sock || true
sleep 3
