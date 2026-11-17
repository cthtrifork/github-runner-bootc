# Testing

Everything runs in GitHub Actions. The slow tests are opt-in with a PR label, so a normal PR only runs the checks that
take seconds.

## On every PR

| Check | What it covers |
|---|---|
| `actionlint`, `zizmor` (pedantic) | the workflows |
| `shellcheck`, `hadolint` | the scripts and the Containerfile |
| `image refs` | the runner image tag is the same in the Containerfile and the Quadlet unit (`tests/check-image-refs.sh`) |
| `check title` | the PR title is a Conventional Commit |
| `Validate Renovate config`, `dry run` | the Renovate configuration |
| `Build ... image` | both images build (the PR image is only pushed when a label asks for it) |

## Opt-in labels

| Label | What it does |
|---|---|
| `push` | publishes the PR image as `pr-<number>` |
| `e2e` | boots both images in QEMU and runs `tests/system-test.sh` inside them |
| `e2e-live` | `e2e`, then registers a real runner on the offline image's VM and runs a job on it |
| `disk` | builds the raw disk image without uploading it |
| `iso` | installs an ISO unattended in QEMU and runs the system tests on the installed disk |

`disk` and `iso` use the PR image, so add `push` (or `e2e`) first and wait for the build.

### `e2e`

1. `bootc install to-disk` writes the image into a sparse raw disk (`.github/actions/install-disk`).
2. QEMU boots it with only an SSH forward on port 2222 (`.github/actions/boot-vm`, SSH key generated for the run).
   - The **offline** image boots with the network restricted (`restrict=on`), so everything must work without a
     registry or internet. This is the airgap test; the journal must not contain a registry lookup.
   - The **default** image boots with a network, and its first boot pulls the runner image.
3. `tests/system-test.sh` runs inside the VM (`tests/vm-ssh.sh bash -s < tests/system-test.sh`). It checks the units and
   timers, that the idle runner is not running, that the runner image is in the container storage, that the generated
   unit never pulls, and that the runner container starts from the local image and fails on the missing JIT config, not
   on the network.
4. `tests/vm-stop.sh` saves the journal and shuts the VM down cleanly.

### `e2e-live`

After the offline test the VM is shut down cleanly, booted again with a network, and:

1. `tests/live-test.sh seed` runs `github-runner-seed-app` in the VM (the App key goes over stdin) with the label
   `e2e-<run id>`.
2. The `live job` of the same run has `runs-on: [self-hosted, e2e-<run id>]`, so only this VM's runner can take it.
3. `tests/live-test.sh wait` waits for that job and checks that the runner container was replaced after its job (a second
   JIT config was minted).
4. `tests/live-test.sh cleanup` removes any runner still registered with the run's label. A failed VM test cancels the
   run so the live job does not wait for a runner that never comes.

It needs the variables `RUNNER_APP_CLIENT_ID` and `RUNNER_INSTALLATION_ID` and the secret `RUNNER_APP_PRIVATE_KEY`, and
only runs for pull requests from the same repository.

### `iso`

The test builds the ISO with an unattended kickstart (`tests/iso-test.toml.in`: partitions, an ephemeral SSH key for
root, `poweroff`), installs it into an empty disk with QEMU and OVMF (`tests/iso-install.sh`), boots the installed disk
and runs `tests/system-test.sh`. The ISO that is published is the interactive one (`iso.toml`), which cannot be scripted.

## Publishing and downloads

- `build` has read-only permissions and runs the pull request's own build action. It hands the rechunked image to
  `publish` as an artifact. `publish` is the only job that can write packages and attestations; it runs no code from the
  checkout. It runs in the environment `publish` (main, the weekly run) or `publish-pr` (a labelled PR).
- The environments and repository settings that make this hold are not in the code: see [publishing-setup.md](publishing-setup.md).
- Disk images and ISOs: the build job has no secrets. A manual run on `main` passes the file as an artifact to the `upload`
  job, which runs on the talos-gitops scale set `arc-files-bootc` (environment `file-upload`, branch `main`) and PUTs it,
  public, to the file server; Cloudflare R2 serves it. The token is the runner's own `FILESERVER_TOKEN`, not a repository secret.
- Verify a release by identity: `gh attestation verify oci://<image>@<digest> -R cthtrifork/github-runner-bootc --signer-workflow cthtrifork/github-runner-bootc/.github/workflows/build.yaml --source-ref refs/heads/main`

## Lessons

- A VM must be shut down with `poweroff`, not by killing QEMU: the loaded runner image is several GiB that have to reach
  the disk before the next boot.
- The ISO job runs on `ubuntu-24.04`: osbuild cannot mount `/dev` on 26.04.
- A label that starts no workflow must not cancel a running build, so the build only cancels on the labels it reads.

## Locally

```
actionlint
zizmor --persona pedantic .github
shellcheck --severity=warning tests/*.sh system_files/usr/libexec/github-runner/* system_files/usr/bin/*
hadolint github-runner.containerfile
tests/check-image-refs.sh
```

`tests/system-test.sh` runs inside any booted image, for example a VM installed from the disk image.
