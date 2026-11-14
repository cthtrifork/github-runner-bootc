#!/usr/bin/env bash
# Install an ISO into an empty disk with QEMU and UEFI firmware, unattended: tests/iso-install.sh <iso> <disk>
# The kickstart ends with poweroff, which ends QEMU (-no-reboot).
set -euo pipefail

iso="${1:?Usage: $0 <iso> <disk>}"
disk="${2:?Usage: $0 <iso> <disk>}"

sudo apt-get install -y --no-install-recommends -qq qemu-system-x86 ovmf
truncate -s 40G "$disk"
cp /usr/share/OVMF/OVMF_VARS_4M.fd out/ovmf-vars.fd
sudo timeout 40m qemu-system-x86_64 -name iso-install -enable-kvm -cpu host -smp "$(nproc)" -m 6G -no-reboot \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
    -drive if=pflash,format=raw,file=out/ovmf-vars.fd \
    -drive if=virtio,file="$disk",format=raw \
    -cdrom "$iso" -boot d \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -display none -serial file:out/install.log
