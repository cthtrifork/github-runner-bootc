# Image signing

The OS images (`ghcr.io/cthtrifork/github-runner-bootc` and `ghcr.io/cthtrifork/offline-github-runner-bootc`) are signed
with a cosign key pair when they are built on `main`. The hosts will refuse an image of ours that is not signed by it
(tracked in [#42](https://github.com/cthtrifork/github-runner-bootc/issues/42)).

Why a key and not keyless signing: the host checks signatures with podman's `policy.json`, and its keyless (Fulcio) rule only
accepts an email identity. A GitHub Actions certificate names a workflow, not an email, so it cannot be expressed there.

## How it works

- The `publish` job of `build.yaml` signs the pushed digest with `cosign sign --key` (cosign **v2**, which writes the `sha256-<digest>.sig`
  tag that podman and bootc read; v3 writes a bundle format they do not). No transparency log upload: the host needs no Rekor.
- The private key and its password are secrets of the environment `publish` (main only). A pull request build runs in
  `publish-pr`, never has them and is not signed.
- The signature is a tag of the package, so the cleanup workflows keep every `sha256-*` tag.

## Set it up (once)

1. On a machine you trust, with cosign v2: `cosign generate-key-pair`. Choose a password. It writes `cosign.key` (encrypted) and `cosign.pub`.
2. GitHub > **Settings > Environments > `publish` > Environment secrets**: add `COSIGN_PRIVATE_KEY` (the contents of `cosign.key`) and
   `COSIGN_PASSWORD`. Keep `cosign.key` and the password in your password manager and delete the local copy.
3. Send the contents of `cosign.pub` (public) to be committed; the host policy uses it.

Until step 2 is done the signing step only warns (`COSIGN_PRIVATE_KEY is not set`) and the images are unsigned.

## Check a signature

```sh
cosign verify --key cosign.pub --insecure-ignore-tlog=true ghcr.io/cthtrifork/github-runner-bootc:latest
```

## Rolling it out to the hosts

1. This step: sign every build of `main`. Hosts enforce nothing yet.
2. After a signed release exists and the check above passes: ship `cosign.pub`, `/etc/containers/policy.json` (requires a
   `sigstoreSigned` signature with `signedIdentity: matchRepository` for our two images) and a `registries.d` entry with
   `use-sigstore-attachments: true`, and make signing mandatory in `build.yaml`. A host moves to that release with its old policy, then enforces it.

## Rotating the key

Generate a new pair, put both public keys in the policy (`keyPaths`), release, then replace the secrets and release again, then drop the old public key.
