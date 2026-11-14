# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Bootc host for ephemeral GitHub Actions runners. Contains no secrets: the GitHub App credentials are seeded on the
# running host (github-runner-seed-app). The runner itself is a container (a logically bound image, so the host needs no
# registry at boot).
FROM quay.io/fedora/fedora-bootc:45

# podman and friends run the Quadlet container; jq/openssl/curl mint the JIT config; skopeo is for debugging mirrors;
# firmware and microcode are for bare metal; qemu-guest-agent is a no-op unless the host is a VM; chrony keeps time (point
# it at an internal NTP server on an airgapped site).
RUN dnf -y install --setopt=install_weak_deps=False \
        podman skopeo netavark aardvark-dns passt fuse-overlayfs crun \
        jq curl openssl bash git-core rsync \
        chrony NetworkManager openssh-server \
        linux-firmware microcode_ctl smartmontools lm_sensors qemu-guest-agent \
    && dnf clean all

RUN { \
      echo 'VARIANT="GitHub runner bootc OS"'; \
      echo 'VARIANT_ID=com.github.cthtrifork.github-runner-bootc'; \
    } >> /usr/lib/os-release

COPY system_files/ /

# Logically bound image: bootc pulls it at install/switch/upgrade (docs: bootc-logically-bound-images). Only the Image=
# line of the linked file is read.
RUN mkdir -p /usr/lib/bootc/bound-images.d \
    && ln -s /usr/share/containers/systemd/github-runner.image /usr/lib/bootc/bound-images.d/github-runner.image

# Updates are staged and drained by github-runner-update.timer; the stock timer would reboot in the middle of a job.
RUN systemctl disable bootc-fetch-apply-updates.timer || true \
    && systemctl mask bootc-fetch-apply-updates.timer \
    && systemctl enable chronyd.service NetworkManager.service sshd.service qemu-guest-agent.service \
        github-runner-update.timer github-runner-prune.timer

RUN bootc container lint
