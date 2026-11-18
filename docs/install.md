# Install guide

From a downloaded ISO to the first job. You need a GitHub repository (or organization) you administer, and a machine
with at least 60 GiB of disk (see [Disk space](../README.md#disk-space)).

## 1. Download

| ISO | Use it when |
|---|---|
| [github-runner-bootc-latest.iso](https://shared-files.portableinfo.cloud/github-runner-bootc-latest.iso) (2.2 GiB) | the host can reach a registry; the runner image is pulled on the first boot |
| [github-runner-offline-bootc-latest.iso](https://shared-files.portableinfo.cloud/github-runner-offline-bootc-latest.iso) (2.7 GiB) | the host has no registry or network except GitHub (airgap); the runner image is inside |

Each release replaces its file, so there is one current ISO per image and no older versions.

## 2. Verify

Every ISO has a signed build provenance attestation (Sigstore) from this repository's release workflow. With the
[GitHub CLI](https://cli.github.com/) (`gh auth login` once):

```sh
gh attestation verify github-runner-bootc-latest.iso -R cthtrifork/github-runner-bootc
```

It prints the SHA-256 of the file and the workflow that built it; the SHA-256 of the ISO is also in the summary of the
release's `Create ISO` run. A file that was changed or did not come from this repository fails the check. ISOs from before this
check was added have no attestation.

## 3. Install

1. Write the ISO to a USB stick: `sudo dd if=github-runner-bootc-latest.iso of=/dev/sdX bs=4M conv=fsync status=progress`
   (check `sdX` with `lsblk` first: it is overwritten), or attach it to the virtual machine.
2. Boot the machine from it. The installer (Fedora's Anaconda) asks for the target disk, the network and an administrator
   account. Make the account an administrator, so that it can use `sudo`. No user, password or key is baked into the image.
3. Reboot into the installed system and log in as that account (see below).

### Logging in

- **Console:** on bare metal, the keyboard and screen, or the machine's remote console (IPMI/BMC, or the hypervisor's console for a VM).
- **SSH:** `sshd` is enabled: `ssh <account>@<host>`. A disk written with `bootc install ... --root-ssh-authorized-keys` (see [Build a disk image yourself](../README.md#build-a-disk-image-yourself))
  also lets `root` in with that key.
- **sudo:** the installer's administrator account is in the `wheel` group, which can use `sudo`.
- A login shell shows how to seed the host until the runners are seeded (step 5), then stops.
- Nothing is baked into the image: no user, password or SSH key. If you lose access, reinstall.

## 4. Create the GitHub App

The runners register themselves with a GitHub App. The App key stays on the host; it is never part of the image.

1. GitHub > **Settings** > **Developer settings** > **GitHub Apps** > **New GitHub App** (for an organization, the same under
   the organization's settings).
2. Name it, give any homepage URL, and untick **Webhook > Active**.
3. Permissions:
   - for one repository: **Repository permissions > Administration: Read and write**;
   - for an organization: **Organization permissions > Self-hosted runners: Read and write** (this scope does not need
     Administration, which is safer: a stolen key then cannot change repository settings).
4. Choose where it can be installed (**Only on this account** is fine) and **Create GitHub App**.
5. On the App's page note the **Client ID**, then **Generate a private key**: a `.pem` file is downloaded.
6. **Install App** and select the repository (or all repositories of the organization). The installation ID is the number in
   the URL of the installation's settings page (`/settings/installations/<id>`).

## 5. Seed the host

Copy the key to the host (`scp key.pem <user>@<host>:`), then on the host:

```sh
sudo github-runner-seed-app --scope repo:owner/name --app-id <Client ID> --installation-id <id> key.pem
```

Use `--scope org:name` for an organization. The key is read from the file (or stdin), encrypted (`systemd-creds`, TPM2 when there is one) in
`/etc/github-runner`, and the runner instances start. Delete the `.pem` from the host afterwards.

| Option | What it does |
|---|---|
| `--instances N` | run N runners at once (each needs about 20 GiB of disk for its jobs) |
| `--labels a,b,c` | runner labels (default `self-hosted,Linux,X64,bootc`) |
| `--runner-group-id N` | the organization runner group (default 1) |
| `--isolate-jobs` | wipe the image storage and caches before every job (slower; see Security in the README) |
| `--disk-quota-gb N` | cap each instance's disk with an xfs project quota |
| `--api-url URL` | GitHub Enterprise Server API |

Follow the runners with `journalctl -fu 'github-runner@*'`. They also appear under the repository's **Settings > Actions >
Runners**.

## 6. Run the first job

```yaml
name: hello
on: workflow_dispatch
jobs:
  hello:
    runs-on: [self-hosted, bootc]
    steps:
      - run: id && docker run --rm hello-world
```

Run it from the **Actions** tab. Every job runs in a fresh container; the runner is GitHub's official runner image, with
passwordless `sudo` and a Docker daemon, and without podman, buildah or other tools: a job installs what it needs.

## Next

- A job is **root on the host**: read [Security](../README.md#security) before attaching the host to a repository, and use a
  dedicated host for private or trusted repositories only.
- The host updates itself every night and reboots once its runners are idle.
- Airgapped sites and authenticated registries: [mirrors and private registries](airgap.md).
