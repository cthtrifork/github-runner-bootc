# One-time setup for publishing and file uploads

These GitHub settings cannot be set from the code. `cthtrifork` is a personal account: no runner groups, the repository is the boundary.

## 1. Check the runner scale set

```bash
flux get helmrelease -n arc-runners-system arc-runners-bootc-files
kubectl -n arc-runners-system get autoscalingrunnerset arc-files-bootc
```

Then check that `arc-files-bootc` is listed under **Settings > Actions > Runners**. If not, read the listener log
(`kubectl -n arc-systems logs -l actions.github.com/scale-set-name=arc-files-bootc`): `401` means a wrong App ID, installation ID or
key in `github-auth-bootc-files`; `404` means the App is not installed on this repository or lacks Administration: read and write.

## 2. Environments

**Settings > Environments > New environment**, once per row. For "you approve" tick **Required reviewers**, add yourself and
untick **Prevent self-review**. For "main only" choose **Selected branches and tags** and add the branch rule `main`.

| Environment | Used by | Approval | Branches |
|---|---|---|---|
| `publish` | pushes to main, weekly rebuild | none | main only |
| `publish-pr` | PRs labelled `push`, `e2e`, `e2e-live` | you approve | any |
| `file-upload` | manual disk image / ISO upload | you approve | main only |

## 3. Repository settings

- **Settings > Actions > General > Fork pull request workflows**: **Require approval for all outside collaborators** (the repo is
  public and your cluster runner takes its jobs).
- **Packages** > each package > **Manage Actions access**: only this repository has **Write**.

GitHub cannot protect `latest` and `main-*` package tags. The `publish-pr` approval and the `main`-only `publish` environment guard
them. Keep write access to the repository to yourself.

## 4. First runs

- **PR image**: add the label `push`. When **Build** is done, the **Publish** job waits: **Review deployments** > `publish-pr` >
  **Approve and deploy**.
- **Upload**: **Actions > Create disk image > Run workflow** on `main` (tag `latest`, variant `offline`, your public SSH key). When
  the disk job is done, approve `file-upload` the same way. The first run starts the runner pod (about a minute). The file is then at
  `https://shared-files.portableinfo.cloud/<name>` (the name is in the run summary).

| Symptom | Cause |
|---|---|
| `upload` waits for a runner | scale set not registered (step 1) |
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
