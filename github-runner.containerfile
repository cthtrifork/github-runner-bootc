# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Bootc host for ephemeral GitHub Actions runners; no secrets in the image. EMBED_RUNNER_IMAGE=true builds the offline
# variant, which carries the runner image; the default variant pulls it on the first boot.
FROM quay.io/fedora/fedora-bootc:45 AS base

# only the Image= line of the Quadlet unit reaches the build below, so editing the unit does not rebuild the embedded layer
FROM base AS runner-ref
COPY system_files/usr/share/containers/systemd/github-runner@.container /unit
RUN sed -n 's/^Image=//p' /unit > /ref

FROM base

RUN dnf -y install --setopt=install_weak_deps=False \
        podman skopeo netavark aardvark-dns passt fuse-overlayfs crun \
        jq curl openssl bash git-core rsync \
        chrony NetworkManager openssh-server \
        linux-firmware microcode_ctl smartmontools lm_sensors qemu-guest-agent \
    && dnf clean all

# Fedora 45 keeps its repositories in /usr/share/dnf5/repos.d; bootc-image-builder reads /etc/yum.repos.d
RUN cp /usr/share/dnf5/repos.d/fedora.repo /usr/share/dnf5/repos.d/fedora-updates.repo /etc/yum.repos.d/

# The runner image of the Quadlet unit, embedded as an OCI directory (a plain copy, no privileges needed) before anything
# that changes often, so updates reuse its large layer.
ARG EMBED_RUNNER_IMAGE=false
COPY --from=runner-ref /ref /tmp/runner-ref
RUN mkdir -p /usr/share/github-runner \
    && if [ "${EMBED_RUNNER_IMAGE}" = true ]; then \
         ref="$(cat /tmp/runner-ref)" \
         && skopeo copy --retry-times 3 "docker://${ref}" "oci:/usr/share/github-runner/runner-image:${ref##*:}" \
         && touch /usr/share/github-runner/offline; \
       fi \
    && rm -f /tmp/runner-ref

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
