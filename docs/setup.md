# Repository setup

What the workflows in this repository expect.

| Kind | Name | Used by |
|---|---|---|
| Variable | `RENOVATE_APP_CLIENT_ID` | `renovate.yaml` |
| Secret | `RENOVATE_APP_PRIVATE_KEY` | `renovate.yaml` |
| Secret | `AZURE_STORAGE_CONNECTION_STRING` | `create-disk-image.yaml` |
| Variable | `AZURE_STORAGE_CONTAINER` | `create-disk-image.yaml` |

The Renovate GitHub App must be installed on this repository.

The same GitHub App (`cthtrifork-runner-bootc`, repository permission *Administration: read and write*) serves the
hosts and the `e2e-live` test. For the test, set:

| Kind | Name |
|---|---|
| Variable | `RUNNER_APP_CLIENT_ID`, `RUNNER_INSTALLATION_ID` |
| Secret | `RUNNER_APP_PRIVATE_KEY` |

The test uses a token limited to this repository, whatever else the App is installed on.

Create the labels `e2e`, `e2e-live`, `push` and `disk` (`disk` dry-runs the disk image build on a PR, without the upload).
