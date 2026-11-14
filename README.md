# github-runner-bootc

A [bootc](https://containers.github.io/bootc/) image (Fedora 45, x86_64) that turns a VM or a bare-metal host into
ephemeral self-hosted GitHub Actions runners. Every job runs in a fresh container from the
[ARC runner image](https://github.com/cthtrifork/talos-gitops), which ships inside the OS image, so the host needs no
registry to run (airgap friendly).

## Why

Self-hosted runners usually mean two things to look after: an operating system (patching, drift, snapshots) and the
runner software on top of it (installing, registering, upgrading, cleaning up between jobs). This project makes them
one artifact:

- **One image, one lifecycle.** The OS, the runner and its tooling are built, tested and versioned together. The host
  updates itself atomically and rolls back if something breaks, so there is no separate OS patching or runner upgrade.
- **Clean by default.** Every job runs in a fresh container, so nothing leaks from one job to the next and the host does
  not accumulate state.
- **Nothing to rebuild by hand.** A new host is a disk image plus one seed command; a broken host is replaced, not repaired.
- **Airgap friendly.** The runner image ships inside the OS image, so the host needs no registry, only GitHub.
- **No secrets in the image.** The GitHub App key is seeded at first boot and never baked in.

```mermaid
flowchart LR
    A["1. Get the disk image<br/>(Azure blob)"] --> B["2. Write it to a disk<br/>VM or bare metal"]
    B --> C["3. Boot, then seed the<br/>GitHub App (one command)"]
    C --> D["Jobs run, one fresh<br/>container per job"]
    D --> E["Updates itself at night,<br/>only when idle"]
```

## Use it

1. **Disk image:** run the *Create disk image* workflow (a raw image, zstd compressed, uploaded to Azure blob
   storage), and write it to the disk with `dd`. On a host that already runs bootc, `bootc switch` to the image
   `ghcr.io/cthtrifork/github-runner-bootc`. The runner image is embedded in the OS image, so every installer carries it (an ISO is planned, see #20).
2. **Seed the GitHub App** (Administration: read and write; the key never goes into the image):

   ```
   sudo github-runner-seed-app --scope repo:owner/name --app-id <Client ID> --installation-id <id> [--instances 2] key.pem
   ```

   Use `--scope org:name` for an organization.
3. **Target it** with `runs-on: [self-hosted, bootc]`.

Airgapped sites: point `/etc/containers/registries.conf.d/` at an internal mirror for the OS and runner images, `chrony`
at an internal NTP server, and put extra `Volume=` lines (private CA, mirror config) in
`/etc/containers/systemd/github-runner@.container.d/10-site.conf`. The runner itself only needs GitHub.

## Security

The runner container is privileged (it runs podman and buildah inside), so **a job is root on the host**. Use a
dedicated host and attach it only to private or trusted repositories through a runner group. This repository is public:
never point its own PR workflows at it.

## Development

- [Architecture and flow](docs/architecture.md), [repository setup](docs/setup.md) (secrets, variables, labels).
- Opt-in PR labels: `e2e` boots the image in QEMU with no network; `e2e-live` also registers a real runner and runs a
  job on it; `disk` dry-runs the disk image build; `push` publishes the PR image.
- PR titles follow [Conventional Commits](https://www.conventionalcommits.org/); every change needs review from the code
  owner.
