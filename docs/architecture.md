# Architecture

```mermaid
flowchart LR
    subgraph REG["Registries"]
        direction TB
        OS["OS image<br/>github-runner-bootc<br/>offline-github-runner-bootc"]
        RUN["Runner image<br/>ghcr.io/actions/actions-runner"]
        MIRROR["Internal mirror<br/>(airgapped sites)"]
    end

    subgraph HOST["Host: VM or bare metal (bootc, x86_64)"]
        direction TB
        BOOTC["bootc OS<br/>nightly update, drains first"]
        STORE[("Runner image<br/>in the container storage")]
        subgraph UNITS["systemd: github-runner@N"]
            direction TB
            MINT["mint-jitconfig<br/>single-use JIT config"]
            CTR["Runner container<br/>Docker daemon + one job,<br/>then a fresh one"]
            MINT --> CTR
        end
        SEED["GitHub App credentials<br/>/etc/github-runner, root only"]
        STORE --> CTR
        SEED --> MINT
    end

    GH["GitHub<br/>repository or organization"]
    APP["GitHub App<br/>Administration: read and write"]

    OS -- "install, switch, upgrade" --> BOOTC
    RUN -- "first boot (default image)<br/>or embedded (offline image)" --> STORE
    MIRROR -.-> BOOTC
    MIRROR -.-> STORE
    APP -. "key seeded once" .-> SEED
    MINT -- "installation token,<br/>generate-jitconfig" --> GH
    CTR <-- "job and logs" --> GH
```

## Flow

```mermaid
sequenceDiagram
    autonumber
    participant U as You
    participant H as Host
    participant S as github-runner@N
    participant G as GitHub

    U->>H: install the image
    U->>H: github-runner-seed-app (GitHub App key)

    loop for every job
        S->>G: installation token, then generate-jitconfig (single use)
        S->>S: start the runner container from the local image<br/>(host adds the NAT rule for its Docker bridges; the container starts dockerd, then the runner)
        S->>G: runner connects and waits for a job
        G-->>S: job
        S->>G: logs and result
        Note over S: the container exits, systemd starts a fresh one
    end

    Note over H: Nightly: bootc upgrade stages an update.<br/>Idle runners stop, busy ones finish, then the host reboots.
```
