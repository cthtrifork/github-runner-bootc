# github-runner-bootc

A [bootc](https://containers.github.io/bootc/) image (Fedora, x86_64) that turns a VM or a bare-metal host into an
ephemeral self-hosted GitHub Actions runner. Sister project of
[homeserver-bootc](https://github.com/cthtrifork/homeserver-bootc), whose CI it reuses.

**Status:** bootstrapping. Only the repository tooling (lint, PR title check, self-hosted Renovate) exists so far;
the image comes next.

## Plan in short

- Rootless podman, an unprivileged `runner` user, no secrets in the image. GitHub App credentials are seeded on the
  running host.
- One ephemeral (JIT) runner per job through a `github-runner@.service` template unit.
- Updates by bootc, drained so a reboot never interrupts a job.
- CI: build, rechunk, scan, sign, release, plus an opt-in `e2e` / `e2e-live` pair of PR labels.

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
| Secret | `PAT_RENOVATEBOT` | `renovate.yaml` (ghcr.io lookups) |

The Renovate GitHub App must be installed on this repository.
