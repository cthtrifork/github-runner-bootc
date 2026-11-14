# github-runner-bootc

A [bootc](https://containers.github.io/bootc/) image (Fedora 45, x86_64) that turns a VM or a bare-metal host into
ephemeral self-hosted GitHub Actions runners. Every job runs in a fresh container from the
[ARC runner image](https://github.com/cthtrifork/talos-gitops).

| Image | Runner image | Size | Use it when | Links |
|---|---|---|---|---|
| `ghcr.io/cthtrifork/github-runner-bootc` | pulled once on the first boot | small | the host can reach a registry or a mirror | [package](https://github.com/cthtrifork/github-runner-bootc/pkgs/container/github-runner-bootc) |
| `ghcr.io/cthtrifork/offline-github-runner-bootc` | embedded in the OS image | about 3.5 GiB larger | the host has no registry or network (airgap) | [package](https://github.com/cthtrifork/github-runner-bootc/pkgs/container/offline-github-runner-bootc) |

Both are published with every build of `main` and the weekly rebuild: see the [releases](https://github.com/cthtrifork/github-runner-bootc/releases)
for the tags and the changes, and the [architecture](docs/architecture.md) for how it fits together.

## Why

Self-hosted runners usually mean two things to look after: an operating system (patching, drift, snapshots) and the
runner software on top of it (installing, registering, upgrading, cleaning up between jobs). This project makes them
one artifact:

- **One image, one lifecycle.** The OS, the runner and its tooling are built, tested and versioned together. The host
  updates itself atomically and rolls back if something breaks, so there is no separate OS patching or runner upgrade.
- **Clean by default.** Every job runs in a fresh container, so nothing leaks from one job to the next and the host does
  not accumulate state.
- **Nothing to rebuild by hand.** A new host is a disk image plus one seed command; a broken host is replaced, not repaired.
- **Airgap friendly.** The offline image ships the runner image inside the OS image, so the host needs no registry, only GitHub.
- **No secrets in the image.** The GitHub App key is seeded at first boot and never baked in.

```mermaid
flowchart LR
    A["1. Install the image<br/>VM or bare metal"] --> B["2. Boot it"]
    B --> C["3. Seed the GitHub App<br/>(one command)"]
    C --> D["Jobs run, one fresh<br/>container per job"]
    D --> E["Updates itself at night,<br/>only when idle"]
```

## Use it

1. **Install:** write the raw disk image to the disk with `dd`, or run `bootc switch` to one of the images above on a
   host that already runs bootc. An installer ISO is experimental (see #20 and [Build a disk image yourself](#build-a-disk-image-yourself)).
2. **Seed the GitHub App** (Administration: read and write; the key never goes into the image):

   ```
   sudo github-runner-seed-app --scope repo:owner/name --app-id <Client ID> --installation-id <id> [--instances 2] key.pem
   ```

   Use `--scope org:name` for an organization.
3. **Target it** with `runs-on: [self-hosted, bootc]`.

Airgapped sites: point `/etc/containers/registries.conf.d/` at an internal mirror for the OS and runner images, `chrony`
at an internal NTP server, and put extra `Volume=` lines (private CA, mirror config) in
`/etc/containers/systemd/github-runner@.container.d/10-site.conf`. The runner itself only needs GitHub.

## Build a disk image yourself

Both images are public, so you can build the disk instead of downloading one. You need Linux with rootful podman and about
40 GiB free.

1. Put your public SSH key(s) in `authorized_keys`; they are authorized for `root` on the new host.
2. Build a raw disk (use `offline-github-runner-bootc` for the airgap variant; the disk is sparse, 80G is only its size):

   ```sh
   truncate -s 80G disk.raw
   sudo podman pull ghcr.io/cthtrifork/github-runner-bootc:latest
   sudo podman run --rm --privileged --pid=host --security-opt label=type:unconfined_t \
     -v /dev:/dev -v /run/udev:/run/udev:ro -v /var/lib/containers:/var/lib/containers \
     -v "$PWD:/output" -v "$PWD/authorized_keys:/authorized_keys:ro" \
     ghcr.io/cthtrifork/github-runner-bootc:latest \
     bootc install to-disk --via-loopback --generic-image --filesystem xfs \
       --root-ssh-authorized-keys /authorized_keys /output/disk.raw
   ```

3. Write it to a disk (`sudo dd if=disk.raw of=/dev/sdX bs=4M conv=fsync status=progress`), or try it in QEMU:

   ```sh
   qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 6G -drive if=virtio,file=disk.raw,format=raw \
     -netdev user,id=n0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=n0
   ssh -p 2222 root@localhost
   ```

4. Seed the GitHub App as in [Use it](#use-it).

This is how `create-disk-image.yaml` builds it. An installer ISO (experimental, see #20) is built by `create-iso.yaml` with
[bootc-image-builder](https://github.com/osbuild/image-builder) and `iso.toml`: `--type iso --rootfs xfs --config iso.toml`.

## Security

The runner container is privileged (it runs podman and buildah inside), so **a job is root on the host**. Use a
dedicated host and attach it only to private or trusted repositories through a runner group. This repository is public:
never point its own PR workflows at it.

## Contributing

- [Architecture](docs/architecture.md): how the host, the runner and GitHub fit together.
- [Testing](docs/testing.md): the checks on every PR and the opt-in labels (`e2e`, `e2e-live`, `disk`, `iso`).
- PR titles follow [Conventional Commits](https://www.conventionalcommits.org/). Every merge of an image change to `main` publishes a
  [release](https://github.com/cthtrifork/github-runner-bootc/releases).
