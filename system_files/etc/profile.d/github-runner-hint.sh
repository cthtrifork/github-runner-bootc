# Shown at an interactive login until the runners are seeded (github-runner-seed-app links the instances into multi-user.target.wants).
if [ -t 1 ] && [ ! -e /etc/systemd/system/multi-user.target.wants/github-runner@1.service ]; then
    echo "This host has no GitHub App yet, so no runner is running. Seed it:"
    echo "  sudo github-runner-seed-app --scope repo:<owner>/<repo> --app-id <Client ID> --installation-id <id> key.pem"
    echo "Guide: https://github.com/cthtrifork/github-runner-bootc/blob/main/docs/install.md"
fi
