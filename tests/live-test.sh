#!/usr/bin/env bash
# The e2e-live steps that talk to the VM and to GitHub: seed | wait | cleanup
set -euo pipefail

vm="$(dirname "$0")/vm-ssh.sh"

case "${1:?Usage: $0 seed|wait|cleanup}" in
seed)
    printf '%s\n' "$RUNNER_APP_PRIVATE_KEY" | "$vm" \
        "github-runner-seed-app --scope repo:${GITHUB_REPOSITORY} --app-id ${RUNNER_APP_CLIENT_ID} --installation-id ${RUNNER_INSTALLATION_ID} --labels self-hosted,Linux,X64,bootc,e2e-${RUN_ID}"
    ;;
wait)
    for _ in $(seq 1 40); do
        state="$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${RUN_ID}/jobs" --jq '[.jobs[] | select(.name=="live job") | .conclusion] | first // ""')"
        [ -n "$state" ] && break
        sleep 15
    done
    echo "live job conclusion: ${state:-none}"
    [ "$state" = "success" ]
    # after its job the container is replaced, which mints a second JIT config
    for _ in $(seq 1 24); do
        mints="$("$vm" "journalctl -u github-runner@1.service --no-pager | grep -c 'JIT runner configuration minted'" || true)"
        echo "JIT configs minted so far: ${mints:-0}"
        [ "${mints:-0}" -ge 2 ] && exit 0
        sleep 5
    done
    echo "::error::the runner container was not replaced after its job"
    exit 1
    ;;
cleanup)
    gh api "repos/${GITHUB_REPOSITORY}/actions/runners" --paginate \
        --jq ".runners[] | select(.labels[].name == \"e2e-${RUN_ID}\") | .id" |
        xargs -r -I{} gh api -X DELETE "repos/${GITHUB_REPOSITORY}/actions/runners/{}"
    ;;
*) echo "unknown command" >&2; exit 1 ;;
esac
