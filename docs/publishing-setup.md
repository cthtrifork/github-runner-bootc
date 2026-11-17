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
kubectl -n arc-runners-system get autoscalingrunnerset arc-runners-bootc-files
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

```bash
repo=cthtrifork/github-runner-bootc
me="$(gh api user --jq .id)"

# publish: only main may deploy. No reviewer by default: a reviewer here also gates every merge and the weekly rebuild.
gh api -X PUT "repos/$repo/environments/publish" --input - <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
gh api -X POST "repos/$repo/environments/publish/deployment-branch-policies" -f name=main -f type=branch

# file-upload: only main, and you approve each upload
gh api -X PUT "repos/$repo/environments/file-upload" --input - <<JSON
{"reviewers": [{"type": "User", "id": $me}], "prevent_self_review": false,
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
gh api -X POST "repos/$repo/environments/file-upload/deployment-branch-policies" -f name=main -f type=branch

# publish-pr: you approve each PR image push (a PR can come from any same-repo branch, so no branch rule)
gh api -X PUT "repos/$repo/environments/publish-pr" --input - <<JSON
{"reviewers": [{"type": "User", "id": $me}], "prevent_self_review": false}
JSON

gh api "repos/$repo/environments" --jq '.environments[].name'   # expect publish, publish-pr, file-upload (and copilot)
```

If you want an approval on every release too, add the same `reviewers` block to `publish`. With a single maintainer the approver is
yourself, so it is a pause for you to check what is about to be pushed, not a second pair of eyes.

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

```bash
# the PR image: add a label; the publish job pauses for your approval
gh pr edit <pr> --add-label push
# approve in the web UI: the run page shows "Review deployments" (publish-pr)

# the upload: only a manual run on main starts it
gh workflow run "Create disk image" --ref main -f tag=latest -f variant=offline -f authorized_keys="$(cat ~/.ssh/id_ed25519.pub)"
gh run watch
```

The `upload` job waits for your approval (`file-upload`), then PUTs the file. The summary shows the name; the public URL is
`https://shared-files.portableinfo.cloud/<name>`. Check it:

```bash
curl -fsSI https://shared-files.portableinfo.cloud/<name> | head -5
```

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
