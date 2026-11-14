# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Bootc host for ephemeral GitHub Actions runners. Contains no secrets: the GitHub App credentials are seeded on the
# running host (github-runner-seed-app). The runner itself is a container whose image is embedded in this image, so the
# host needs no registry or network and any installer (ISO, raw disk, bootc switch) carries it.
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

# The runner image (the one the ARC scale sets use), embedded as an OCI directory: a plain file copy that needs no
# privileges at build time. github-runner-image-load.service loads it into the host's container storage at first boot.
# It comes right after the packages and before anything that changes often, so its (large) layer is reused by updates.
# Keep the tag equal to the Image= line of github-runner@.container (tests/check-image-refs.sh).
ARG RUNNER_IMAGE=ghcr.io/cthtrifork/talos-gitops/github-actions-runner
ARG RUNNER_IMAGE_TAG=v0.11.0 # renovate: datasource=docker depName=ghcr.io/cthtrifork/talos-gitops/github-actions-runner
RUN mkdir -p /usr/share/github-runner \
    && skopeo copy --retry-times 3 "docker://${RUNNER_IMAGE}:${RUNNER_IMAGE_TAG}" "oci:/usr/share/github-runner/runner-image:${RUNNER_IMAGE_TAG}"

RUN { \
      echo 'VARIANT="GitHub runner bootc OS"'; \
      echo 'VARIANT_ID=com.github.cthtrifork.github-runner-bootc'; \
    } >> /usr/lib/os-release

COPY system_files/ /

# Updates are staged and drained by github-runner-update.timer; the stock timer would reboot in the middle of a job.
RUN systemctl disable bootc-fetch-apply-updates.timer || true \
    && systemctl mask bootc-fetch-apply-updates.timer \
    && systemctl enable chronyd.service NetworkManager.service sshd.service qemu-guest-agent.service \
        github-runner-image-load.service github-runner-update.timer github-runner-prune.timer

RUN bootc container lint
