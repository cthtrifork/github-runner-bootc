# Mirrors and private registries

For a site whose hosts cannot reach `ghcr.io`, or must pull from an internal registry that needs a login. No credential is
ever baked into the image: you put them on the host.

## What to mirror

| What | Why |
|---|---|
| `ghcr.io/cthtrifork/github-runner-bootc` or `ghcr.io/cthtrifork/offline-github-runner-bootc` (the tags you use) | the OS image, for `bootc upgrade` |
| the **signatures** of those images: the tag `sha256-<digest>.sig` next to each image tag's digest | the host refuses an unsigned image of ours (see [signing](signing.md)); an image mirrored without its signature is refused |
| `ghcr.io/actions/actions-runner` (the tag in `github-runner.containerfile`) | the runner image, only for the default image variant (the offline image has it inside) |
| a Fedora repository (see below) | only if a host runs `dnf`, or you build the ISO yourself |

Copy an image and its signature with `skopeo`, for example (use `--all` for a multi-arch image, `--preserve-digests` so the digest stays the same):

```sh
skopeo copy --preserve-digests docker://ghcr.io/cthtrifork/github-runner-bootc:latest docker://registry.example.com/mirror/github-runner-bootc:latest
skopeo copy docker://ghcr.io/cthtrifork/github-runner-bootc:sha256-<digest>.sig docker://registry.example.com/mirror/github-runner-bootc:sha256-<digest>.sig
```

## Point the host at the mirror

Remap the registry with a drop-in. The host still names the image `ghcr.io/cthtrifork/...`, so the signature policy keeps
applying to it; only the place it is pulled from changes
([containers-registries.conf](https://github.com/containers/image/blob/main/docs/containers-registries.conf.5.md#remapping-and-mirroring-registries)):

```toml
# /etc/containers/registries.conf.d/50-mirror.conf
[[registry]]
prefix = "ghcr.io/cthtrifork"
location = "ghcr.io/cthtrifork"
[[registry.mirror]]
location = "registry.example.com/mirror"
```

Repeat it for `ghcr.io/actions` (the runner image). `bootc` and `podman` both read it.

## Log in to an authenticated registry

bootc reads its credentials from `/etc/ostree/auth.json`
([bootc: private registries](https://github.com/bootc-dev/bootc/blob/main/docs/src/bootc-registries-and-offline.7.md)). Log in once on the host, as root, writing there (the file is `0600`):

```sh
sudo podman login --authfile /etc/ostree/auth.json registry.example.com
```

`podman` looks elsewhere, so the one `podman pull` that the host does itself (the runner image of the default variant, by
`github-runner-image-load.service`) needs the same file. A drop-in does that:

```ini
# /etc/systemd/system/github-runner-image-load.service.d/auth.conf
[Service]
Environment=REGISTRY_AUTH_FILE=/etc/ostree/auth.json
```

then `sudo systemctl daemon-reload`. For an interactive `sudo podman pull` use `--authfile /etc/ostree/auth.json`.

The credentials stay on the host (a pull-only token is enough); a reinstall needs them again.

## Fedora repositories and time

- The image's `/etc/yum.repos.d/fedora.repo` and `fedora-updates.repo` point at `mirrors.dotsrc.org` (the `FEDORA_MIRROR` build argument).
  Change their `baseurl` to an internal mirror of Fedora 45, or build the image with another `FEDORA_MIRROR`.
- Point `chrony` at an internal NTP server (`/etc/chrony.conf`): token and certificate checks need the right time.
- The runner itself only needs GitHub; put a private CA or proxy settings in
  `/etc/containers/systemd/github-runner@.container.d/10-site.conf` (extra `Volume=` and `Environment=` lines).

## Offline updates from a USB drive

Copy the OS image to an OCI directory, carry it over, and use `bootc switch --transport oci /path/to/image.oci` once, then
`bootc upgrade --apply`. The signature policy applies to the `docker` transport only, so a directory is accepted as is: check
where it came from (`cosign verify`, see [signing](signing.md)) before you switch.

Not tested against a real authenticated registry: the commands come from the bootc and containers documentation.
