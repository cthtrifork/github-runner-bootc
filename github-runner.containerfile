# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Bootc host for ephemeral GitHub Actions runners; no secrets in the image. EMBED_RUNNER_IMAGE=true builds the offline
# variant, which carries the runner image; the default variant pulls it on the first boot.
FROM quay.io/fedora/fedora-bootc:45

RUN dnf -y install --setopt=install_weak_deps=False \
        podman skopeo netavark aardvark-dns passt fuse-overlayfs crun \
        jq curl openssl bash git-core rsync \
        chrony NetworkManager openssh-server \
        linux-firmware microcode_ctl smartmontools lm_sensors qemu-guest-agent \
    && dnf clean all

# Embedded as an OCI directory (a plain copy, no privileges needed) before anything that changes often, so updates reuse
# its large layer. The tag must equal the Image= line of github-runner@.container (tests/check-image-refs.sh).
ARG RUNNER_IMAGE=ghcr.io/cthtrifork/talos-gitops/github-actions-runner
ARG RUNNER_IMAGE_TAG=v0.11.0 # renovate: datasource=docker depName=ghcr.io/cthtrifork/talos-gitops/github-actions-runner
ARG EMBED_RUNNER_IMAGE=false
RUN mkdir -p /usr/share/github-runner \
    && if [ "${EMBED_RUNNER_IMAGE}" = true ]; then \
         skopeo copy --retry-times 3 "docker://${RUNNER_IMAGE}:${RUNNER_IMAGE_TAG}" "oci:/usr/share/github-runner/runner-image:${RUNNER_IMAGE_TAG}" \
         && touch /usr/share/github-runner/offline; \
       fi

RUN { \
      echo "VARIANT=\"GitHub runner bootc OS$([ "${EMBED_RUNNER_IMAGE}" = true ] && echo ' (offline)')\""; \
      echo 'VARIANT_ID=com.github.cthtrifork.github-runner-bootc'; \
    } >> /usr/lib/os-release

COPY system_files/ /

# github-runner-update.timer drains the runners before it reboots; the stock timer would not.
RUN systemctl disable bootc-fetch-apply-updates.timer || true \
    && systemctl mask bootc-fetch-apply-updates.timer \
    && systemctl enable chronyd.service NetworkManager.service sshd.service qemu-guest-agent.service \
        github-runner-image-load.service github-runner-update.timer github-runner-prune.timer

RUN bootc container lint
