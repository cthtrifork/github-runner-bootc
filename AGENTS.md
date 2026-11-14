# Notes for coding agents

- Work in a git worktree, never switch branches in the shared checkout.
- Commit messages and PR titles use Conventional Commits (`type(scope): summary`); the `PR title` workflow enforces it.
- Pin GitHub Actions by commit SHA with a version comment (Renovate keeps them current). Put workflow `permissions:`
  at the least privilege and run `actionlint` and `zizmor --persona pedantic .github` before pushing.
- Versions of tools installed in the image or CI carry a `# renovate: datasource=... depName=...` comment.
- Never put secrets in the image, a layer, or a build argument.
- Never target this public repository's PR workflows at a self-hosted runner.
