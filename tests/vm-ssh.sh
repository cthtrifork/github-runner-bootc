#!/usr/bin/env bash
# Run a command in the e2e VM: tests/vm-ssh.sh journalctl -b
exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
    -i "${SSH_KEY:-out/ci_ssh_key}" -p 2222 root@localhost "$@"
