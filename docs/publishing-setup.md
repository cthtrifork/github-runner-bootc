# One-time setup for publishing and file uploads

These GitHub settings cannot be set from the code. `cthtrifork` is a personal account: no runner groups, the repository is the boundary.

## 1. Check the runner scale set

```bash
flux get helmrelease -n arc-runners-system arc-runners-bootc-files arc-runners-bootc-iso
kubectl -n arc-runners-system get autoscalingrunnerset arc-files-bootc arc-iso-bootc
```

Then check that `arc-files-bootc` and `arc-iso-bootc` are listed under **Settings > Actions > Runners**. If not, read the listener log
(`kubectl -n arc-systems logs -l actions.github.com/scale-set-name=arc-files-bootc`): `401` means a wrong App ID, installation ID or
key in `github-auth-bootc-files`; `404` means the App is not installed on this repository or lacks Administration: read and write.

## 2. Environments

**Settings > Environments > New environment**, once per row, no reviewers. For "main only" choose **Selected branches and tags** and
add the branch rule `main`. A reviewer would add a click but no protection: a PR that edits the workflow can drop the `environment:` line.

| Environment | Used by | Branches |
|---|---|---|
| `publish` | pushes to main, weekly rebuild | main only |
| `publish-pr` | PRs labelled `push`, `e2e`, `e2e-live` | any |
| `file-upload` | manual disk image upload, and the ISO `publish` job | main only |

## 3. Repository settings

- **Settings > Actions > General > Fork pull request workflows**: **Require approval for all outside collaborators** (the repo is
  public and your cluster runner takes its jobs).
- **Packages** > each package > **Manage Actions access**: only this repository has **Write**.

GitHub cannot protect `latest` and the release package tags. The `push` label (write access only) and the `main`-only `publish` environment guard
them. Keep write access to the repository to yourself.

## 4. First runs

- **PR image**: add the label `push`.
- **Disk image upload**: **Actions > Create disk image > Run workflow** on `main` (tag `latest`, variant `offline`, your public SSH key). The first run starts the runner pod (about a minute). The file is then at
  `https://shared-files.portableinfo.cloud/<name>` (the name is in the run summary).
- **ISOs**: every release builds both and replaces `github-runner-latest.iso` and `github-runner-offline-latest.iso`. To run one by hand:
  **Actions > Create ISO > Run workflow** on `main` with the tag `latest` or a release tag (`latest-<runner version>-<date>-<n>`) and the variant.
  The build takes about 20 minutes. The file server should hold only those two files: delete any other ISO on its admin page.

| Symptom | Cause |
|---|---|
| `upload` (disk) or `Build and upload the ISO` waits for a runner | scale set not registered (step 1), or the ISO runner cannot be scheduled on the file server's node |
| curl `401` | the pod started before the token existed: re-run |
| curl `422` | SHA-256 mismatch, truncated download: re-run |
| curl `507` / `413` | file server disk full, or over `MAX_FILE_BYTES` (8 GiB) |
| `publish` skipped on a PR | no `push`, `e2e` or `e2e-live` label |

## 5. App key rotation

The key is on every runner VM (`github-runner-seed-app`) and in the cluster Secret. Rotate both, then delete the old key.

## 6. Verify a release

```bash
gh attestation verify oci://ghcr.io/cthtrifork/github-runner-bootc@<digest> -R cthtrifork/github-runner-bootc \
  --signer-workflow cthtrifork/github-runner-bootc/.github/workflows/build.yaml --source-ref refs/heads/main
```
