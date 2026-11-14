# github-runner-bootc

A [bootc](https://containers.github.io/bootc/) image (Fedora, x86_64) that turns a VM or a bare-metal host into an
ephemeral self-hosted GitHub Actions runner. Sister project of
[homeserver-bootc](https://github.com/cthtrifork/homeserver-bootc), whose CI it reuses.

**Status:** first image. Not yet published or run on a real host.

## Plan in short

- Rootless podman, an unprivileged `runner` user, no secrets in the image. GitHub App credentials are seeded on the
  running host.
- One ephemeral (JIT) runner per job through a `github-runner@.service` template unit.
- Updates by bootc, drained so a reboot never interrupts a job.
- CI: build, rechunk, scan, sign, release, plus an opt-in `e2e` / `e2e-live` pair of PR labels.

## How it works

- `github-runner@.container` (Quadlet) runs the runner image from the ARC scale sets
  (`ghcr.io/cthtrifork/talos-gitops/github-actions-runner`), one container per job and one instance per slot.
- Before each start `mint-jitconfig` trades the seeded GitHub App key for a single-use JIT runner configuration.
- The runner image is a bootc *logically bound image*: bootc pulls it at install, switch and upgrade into
  `/usr/lib/bootc/storage`, and the unit uses `Pull=never`, so the host needs no registry to run.
- `github-runner-update.timer` stages OS updates at night and reboots only after the runners are idle.

See [docs/architecture.md](docs/architecture.md) for the architecture and flow diagrams.

### Use it

1. Get a disk image: run the **Create disk image** workflow (raw image with the bound runner image, zstd compressed, uploaded to
   Azure blob storage: it is about 3.7 GiB, too big for a release asset), or `bootc install to-disk` from a host that has the image and the runner image in
   its container storage. An Anaconda ISO would not carry the bound image.
2. Boot it, then seed the GitHub App: `sudo github-runner-seed-app --scope repo:owner/name --app-id N
   --installation-id N [--instances 2] key.pem` (org scope: `--scope org:name`).
3. Airgapped sites: point `/etc/containers/registries.conf.d/` at an internal mirror (OS image and runner image),
   `chrony` at an internal NTP server, and add a drop-in `/etc/containers/systemd/github-runner@.container.d/10-site.conf`
   with extra `Volume=` lines (private CA, mirror config) for the job containers. The runner itself only needs GitHub.

### Tests

PR labels opt in to the slow tests; both need the image to be pushed, which the label does:

- `e2e`: boots the image in QEMU with a restricted network and runs `tests/system-test.sh` (the bound image must be
  usable with no registry).
- `e2e-live`: then boots with a network, registers one ephemeral runner with the label `e2e-<run id>` and runs the
  `live job` on it. Same-repository PRs only.

## Security

This repository is public. Never use a self-hosted runner for this repository's own pull request workflows:
workflows from forks could run code on the host. Attach the runner to private or trusted repositories through a
runner group.

## Contributing

PR titles follow [Conventional Commits](https://www.conventionalcommits.org/) (`type(scope): summary`), checked by
the `PR title` workflow. Every change needs review from the code owner.

### Repository setup the workflows expect

| Kind | Name | Used by |
|---|---|---|
| Variable | `RENOVATE_APP_CLIENT_ID` | `renovate.yaml` |
| Secret | `RENOVATE_APP_PRIVATE_KEY` | `renovate.yaml` |
| Secret | `AZURE_STORAGE_CONNECTION_STRING` | `create-disk-image.yaml` |
| Variable | `AZURE_STORAGE_CONTAINER` | `create-disk-image.yaml` |

The Renovate GitHub App must be installed on this repository.

For the `e2e-live` label, create a second GitHub App for tests (repository permission *Administration: read and
write*, installed on this repository only) and set:

| Kind | Name |
|---|---|
| Variable | `E2E_APP_CLIENT_ID`, `E2E_APP_ID`, `E2E_INSTALLATION_ID` |
| Secret | `E2E_APP_PRIVATE_KEY` |

Create the labels `e2e`, `e2e-live`, `push` and `disk` (`disk` dry-runs the disk image build on a PR, without the upload).
