# One-time setup for publishing and file uploads

The workflows in this repository assume the GitHub settings below. None of them can be set from the code. `cthtrifork` is a
**personal account**, so there are no runner groups and no organization rulesets: the repository itself is the boundary.

Do the steps in order. Replace nothing else: every command uses `-R cthtrifork/github-runner-bootc` or the repository path.

## 0. Order of merges

1. [talos-gitops#944](https://github.com/cthtrifork/talos-gitops/pull/944) (the `arc-files-bootc` scale set and its Secret).
2. This repository's PR with the workflow changes, after steps 1 to 3 below.

## 1. Check the runner scale set (after #944 is merged and Flux has applied it)

```bash
# the scale set exists and registered with GitHub
# (named after runnerScaleSetName, not the HelmRelease; if it is missing, check the HelmRelease first)
flux get helmrelease -n arc-runners-system arc-runners-bootc-files
kubectl -n arc-runners-system get autoscalingrunnerset arc-files-bootc
# the listener pod is running (minRunners is 0, so there is no runner pod until a job is queued)
kubectl -n arc-systems get pods | grep bootc-files
kubectl -n arc-systems logs -l actions.github.com/scale-set-name=arc-files-bootc --tail=20
```

| Log says | Cause | Fix |
|---|---|---|
| `401` / `Bad credentials` | wrong App ID, installation ID or key in `github-auth-bootc-files` | re-create the Secret (`k8s/apps/arc-runner/bootc-files-auth.enc.yaml`) |
| `404` / `Resource not accessible` | the App is not installed on `github-runner-bootc`, or lacks **Administration: read and write** | GitHub > Settings > Developer settings > GitHub Apps > your App > Install App > configure: add this repository |
| nothing, no `autoscalingrunnerset` | Flux has not applied it | `flux get kustomization -A \| grep -i arc`; `flux reconcile kustomization <name> --with-source` |

GitHub shows the scale set under the repository: **Settings > Actions > Runners** (the `arc-files-bootc` entry appears once the listener has registered).

## 2. Create the environments

An environment is where GitHub enforces a branch rule and an approval. `build.yaml` uses `publish` (main and the weekly run) and
`publish-pr` (a pull request with a `push`, `e2e` or `e2e-live` label); the upload jobs use `file-upload`.

Open <https://github.com/cthtrifork/github-runner-bootc/settings/environments> (**Settings > Environments**). An existing
`copilot` environment is not ours: leave it. Repeat the following for each row of the table.

1. Click **New environment**, type the name, click **Configure environment**.
2. **Required reviewers**: tick it, search for your own user, click **Save protection rules** (rows marked "you approve").
3. Untick **Prevent self-review** (you are the only maintainer, so it would block you).
4. **Deployment branches and tags**: open the dropdown, choose **Selected branches and tags**, click **Add deployment branch or tag
   rule**, leave the type on *Branch*, enter `main`, click **Add rule** (rows marked "main only").
5. Leave **Environment secrets** and **variables** empty: nothing in the workflows reads them.

| Environment | Used by | Required reviewer | Deployment branches |
|---|---|---|---|
| `publish` | pushes to main and the weekly rebuild | none (a reviewer here would gate every merge and the weekly run) | main only |
| `publish-pr` | a PR with a `push`, `e2e` or `e2e-live` label | you approve | any branch (a PR can come from any same-repo branch) |
| `file-upload` | the manual disk image and ISO upload | you approve | main only |

When done, the list shows `publish`, `publish-pr` and `file-upload` (plus `copilot`).

With a single maintainer the approver is yourself, so a required reviewer is a pause to check what is about to be pushed, not a
second pair of eyes. To also pause every release, add yourself as required reviewer on `publish`.

## 3. Repository settings (web UI)

1. **Settings > Actions > General > Fork pull request workflows from outside collaborators**: choose
   **Require approval for all outside collaborators**. This repository is public and a runner on your cluster picks up jobs
   for it, so no stranger's workflow may start unapproved.
2. **Settings > Actions > General > Workflow permissions**: **Read repository contents and packages permissions** (the workflows
   ask for more per job).
3. **Settings > Actions > Runners**: the `arc-files-bootc` runner must be listed as a **repository** runner. A personal account has
   no runner groups, so the repository-scoped registration is the boundary: only workflows of this repository can use it.
4. **Packages** (`github-runner-bootc` and `offline-github-runner-bootc` > Package settings > Manage Actions access): this
   repository must be the only one with **Write**.

Honest limits: GitHub offers no tag protection for container packages, so `latest` and `main-*` cannot be locked to `main` the
way a git tag can. What guards them is that `publish-pr` needs your approval and that `publish` only deploys from `main`. A person
with write access to this repository can still change a workflow on a branch; keep write access to yourself.

## 4. First runs

**The PR image.** Open the PR and add the label `push` (right sidebar > **Labels**). Wait for **Build** to finish: the
**Publish** job then shows **Waiting** with a **Review deployments** button on the run page. Tick `publish-pr`, click
**Approve and deploy**.

**The upload.** Only a manual run on main starts it:

1. <https://github.com/cthtrifork/github-runner-bootc/actions/workflows/create-disk-image.yaml> > **Run workflow**.
2. Branch: `main`. Fill in the tag (`latest`), the variant (`offline`) and your public SSH key (paste the contents of
   `~/.ssh/id_ed25519.pub`; public keys only) > **Run workflow**.
3. When the disk job is done, open the run: **Upload to the file server** waits for approval. Click **Review deployments**, tick
   `file-upload`, **Approve and deploy**. The first run also starts the runner pod (a minute or so).
4. The job then PUTs the file. The run summary shows the file name; the public URL is
   `https://shared-files.portableinfo.cloud/<name>`. Open it in a browser: it should start a download.

| Symptom | Cause |
|---|---|
| `upload` stays queued with "waiting for a runner" | the scale set is not registered (step 1) or the Secret is missing |
| `401` from curl | the runner started before the token existed; re-run the job (the pod reads `FILESERVER_TOKEN` at start) |
| `422` | the SHA-256 header did not match the file: the artifact download was truncated; re-run |
| `507` / `413` | the file server disk is full or `MAX_FILE_BYTES` (8 GiB) is exceeded |
| `publish` skipped on a PR | no `push`, `e2e` or `e2e-live` label |

## 5. Rotating the App key

The same App key is in `/etc/github-runner/private-key.pem` on every runner VM (`github-runner-seed-app`) and in the cluster Secret.
Rotate in both places: generate a new key on the App's page, re-run `github-runner-seed-app` on each VM, re-create
`bootc-files-auth.enc.yaml`, then delete the old key.

## 6. Verify what was released

```bash
gh attestation verify oci://ghcr.io/cthtrifork/github-runner-bootc@<digest> -R cthtrifork/github-runner-bootc \
  --signer-workflow cthtrifork/github-runner-bootc/.github/workflows/build.yaml --source-ref refs/heads/main
```
