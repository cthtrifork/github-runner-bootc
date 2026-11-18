# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# Bootc host for ephemeral GitHub Actions runners; no secrets in the image. EMBED_RUNNER_IMAGE=true builds the offline
# variant, which carries the runner image; the default variant pulls it on the first boot.
FROM quay.io/fedora/fedora-bootc:45

RUN dnf -y install --setopt=install_weak_deps=False \
        podman skopeo netavark aardvark-dns passt fuse-overlayfs crun \
        jq curl openssl bash git-core rsync xfsprogs \
        chrony NetworkManager openssh-server \
        linux-firmware microcode_ctl smartmontools lm_sensors qemu-guest-agent \
    && dnf clean all

# Fedora 45 keeps its repositories in /usr/share/dnf5/repos.d; bootc-image-builder reads /etc/yum.repos.d. The copies are pinned
# to one mirror instead of the metalink (only the [fedora] and [updates] sections, the rest of the files stays Fedora's, GPG keys
# included): the cluster runner that builds the ISO only reaches this host (the egress policy of talos-gitops allows it, and
# the homeserver-bootc Containerfiles pin the same one). Keep the two in step.
ARG FEDORA_MIRROR=https://mirrors.dotsrc.org/fedora
RUN cp /usr/share/dnf5/repos.d/fedora.repo /usr/share/dnf5/repos.d/fedora-updates.repo /etc/yum.repos.d/ \
    && sed -i "/^\[fedora\]\$/,/^\[/ s|^metalink=.*|baseurl=${FEDORA_MIRROR}/linux/releases/\$releasever/Everything/\$basearch/os/|" /etc/yum.repos.d/fedora.repo \
    && sed -i "/^\[updates\]\$/,/^\[/ s|^metalink=.*|baseurl=${FEDORA_MIRROR}/linux/updates/\$releasever/Everything/\$basearch/|" /etc/yum.repos.d/fedora-updates.repo \
    && grep -q '^baseurl=' /etc/yum.repos.d/fedora.repo && grep -q '^baseurl=' /etc/yum.repos.d/fedora-updates.repo

# Embedded as an OCI directory (a plain copy, no privileges needed) before anything that changes often, so updates reuse
# its large layer. The tag must equal the Image= line of github-runner@.container (Renovate bumps both together, see .github/renovate.json5).
ARG RUNNER_IMAGE=ghcr.io/actions/actions-runner
ARG RUNNER_IMAGE_TAG=2.338.2 # renovate: datasource=docker depName=ghcr.io/actions/actions-runner
ARG EMBED_RUNNER_IMAGE=false
RUN mkdir -p /usr/share/github-runner \
    && if [ "${EMBED_RUNNER_IMAGE}" = true ]; then \
         skopeo copy --retry-times 3 "docker://${RUNNER_IMAGE}:${RUNNER_IMAGE_TAG}" "oci:/usr/share/github-runner/runner-image:${RUNNER_IMAGE_TAG}" \
         && touch /usr/share/github-runner/offline; \
       fi

RUN { \
      echo "VARIANT=\"GitHub runner bootc OS, runner ${RUNNER_IMAGE_TAG%%-*}$([ "${EMBED_RUNNER_IMAGE}" = true ] && echo ' (offline)')\""; \
      echo 'VARIANT_ID=com.github.cthtrifork.github-runner-bootc'; \
    } >> /usr/lib/os-release

COPY system_files/ /
# the public key of the OS image signatures; /etc/containers/policy.json (from system_files) requires it for our images (docs/signing.md)
COPY cosign.pub /usr/share/github-runner/cosign.pub

# github-runner-update.timer drains the runners before it reboots; the stock timer would not.
RUN systemctl disable bootc-fetch-apply-updates.timer || true \
    && systemctl mask bootc-fetch-apply-updates.timer \
    && systemctl enable chronyd.service NetworkManager.service sshd.service qemu-guest-agent.service \
        github-runner-image-load.service github-runner-update.timer github-runner-prune.timer

RUN bootc container lint
