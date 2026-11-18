# Image signing

The OS images (`ghcr.io/cthtrifork/github-runner-bootc` and `ghcr.io/cthtrifork/offline-github-runner-bootc`) are signed
with a cosign key pair when they are built on `main`. The hosts refuse an image of ours that is not signed by it
([#42](https://github.com/cthtrifork/github-runner-bootc/issues/42)).

Why a key and not keyless signing: the host checks signatures with podman's `policy.json`, and its keyless (Fulcio) rule only
accepts an email identity. A GitHub Actions certificate names a workflow, not an email, so it cannot be expressed there.

## How it works

- The `publish` job of `build.yaml` signs the pushed digest with cosign **v3** in its legacy format (`--new-bundle-format=false`
  and `--registry-referrers-mode=legacy`), which writes the `sha256-<digest>.sig` tag that podman and bootc read. The
  `--use-signing-config=false` option preserves the explicit no-transparency-log-upload setting; the host needs no Rekor.
- The private key and its password are secrets of the environment `publish` (main only). A pull request build runs in
  `publish-pr`, never has them and is not signed.
- The signature is a tag of the package, so the cleanup workflows keep every `sha256-*` tag.

## Set it up (once)

1. On a machine you trust, with cosign v3: `cosign generate-key-pair`. Choose a password. It writes `cosign.key` (encrypted) and `cosign.pub`.
2. GitHub > **Settings > Environments > `publish` > Environment secrets**: add `COSIGN_PRIVATE_KEY` (the contents of `cosign.key`) and
   `COSIGN_PASSWORD`. Keep `cosign.key` and the password in your password manager and delete the local copy.
3. Commit `cosign.pub` (public) to the repository root; the host policy uses it.

Without the secrets the build on `main` fails at the signing step.

## Check a signature

```sh
cosign verify --key cosign.pub --insecure-ignore-tlog=true ghcr.io/cthtrifork/github-runner-bootc:latest
```

## On the hosts

The image ships `cosign.pub` (`/usr/share/github-runner/cosign.pub`), `/etc/containers/policy.json` and
`/etc/containers/registries.d/github-runner.yaml`. The policy requires a `sigstoreSigned` signature from that key
(`signedIdentity: matchRepository`, which is what cosign signatures can express) for `ghcr.io/cthtrifork/github-runner-bootc` and
`ghcr.io/cthtrifork/offline-github-runner-bootc`, and accepts every other image (the official runner image, for one).
`bootc upgrade`, `bootc switch` and `podman pull` all use it, so an unsigned image of ours, including an older tag from before
signing, is refused with "A signature was required, but no signature exists".

- Signing is mandatory in `build.yaml` on `main`: a build without the secrets fails instead of shipping an image the hosts reject.
- A host moves to the first release with this policy under its old policy; from then on it enforces it.
- A site that mirrors the images under another registry name is not covered (the policy matches our repository names): copy the
  signatures with the images and add the same entries for the mirror.

## Rotating the key

Generate a new pair, put both public keys in the policy (`keyPaths`), release, then replace the secrets and release again, then drop the old public key.
