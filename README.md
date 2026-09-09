# Codex Sandbox

`cawad/codex-sandbox` is a ready-to-run development container that provides:

- Codex CLI in a persistent Linux workspace
- key-only SSH access for Codex Desktop, VS Code Remote SSH, or another client
- SSH agent and TCP forwarding
- a private Docker-in-Docker sidecar with Buildx and Compose
- the latest `uv` with a managed Python 3.12 installation
- a configurable loopback port for testing a nested service from the host
- passwordless `sudo` for installing and configuring development tools

Links: [Docker Hub](https://hub.docker.com/r/cawad/codex-sandbox) [GitHub](https://github.com/chrisawad/CodexSandbox)

> [!WARNING]
> This is a trusted development environment, not a hardened isolation boundary.
> The Docker sidecar is privileged, its client certificate grants full control
> of that daemon, and `sandbox` has unrestricted passwordless `sudo` inside its
> own container. Do not run untrusted code.

## Quick start with Docker Compose

You need Docker with the Compose plugin, an SSH key, and a running SSH agent.
The supplied Compose configuration requires the host's Unix `SSH_AUTH_SOCK` and
mounts it into the sandbox. Run Compose from Linux, macOS, or WSL. For WSL, keep
this checkout and its `state` directory in the distro's native Linux
filesystem, such as `~/src/CodexSandbox`, rather than under `/mnt/c`.

### 1. Create `docker-compose.yml`

```yaml
services:
  sandbox:
    image: cawad/codex-sandbox:latest
    restart: unless-stopped
    init: true
    ports:
      - "127.0.0.1:${EXTERNAL_SSHD_PORT:-2222}:2222"
    environment:
      # These env variables express which ports are exposed to DinD
      # to the agent, so it knows how to create links for you
      INTERNAL_SERVICE_PORT: "${INTERNAL_SERVICE_PORT:-3000}"
      EXTERNAL_SERVICE_PORT: "${EXTERNAL_SERVICE_PORT:-3000}"
      GIT_CONFIG_USER_NAME: "${GIT_CONFIG_USER_NAME:-Codex Sandbox}"
      GIT_CONFIG_USER_EMAIL: "${GIT_CONFIG_USER_EMAIL:-}"
    volumes:
      # The ssh-agent socket must be mounted to /ssh-auth.sock
      - "${SSH_AUTH_SOCK}:/ssh-auth.sock"
      # Missing state directories are created automatically
      # The entrypoint scripts sets both dirs to UID/GID 1000:1000
      - ./state/home:/home/sandbox
      - ./state/docker/certs/client:/certs/client:ro
    depends_on:
      docker:
        condition: service_healthy

  docker:
    # The standard DinD image runs a conventional rootful daemon.
    image: docker:29-dind
    restart: unless-stopped
    privileged: true
    ports:
      # Use the same ports given to sandbox
      # This is what actually exposes the port to your local network
      - "${EXTERNAL_SERVICE_PORT:-3000}:${INTERNAL_SERVICE_PORT:-3000}"
    environment:
      DOCKER_TLS_CERTDIR: /certs
    volumes:
      # Persist the docker imagese across re-creates
      - ./state/docker/data:/var/lib/docker
      # Must be same certs given to sandbox
      - ./state/docker/certs:/certs
      # Must be same src dir used by sandbox (to support volume mounts)
      - ./state/home/src:/home/sandbox/src
    healthcheck:
      test: ["CMD", "docker", "info"]
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 10s
```

The loopback-only bindings make SSH and the dedicated test service available
from the host without exposing either to the local network. The Docker daemon is
isolated in the privileged `docker` service, while the SSH/Codex container
remains unprivileged and connects to it over TLS. The host Docker socket is never
mounted.

The workspace is mounted into both services at the identical
`/home/sandbox/src` path. This is required because the daemon, rather than the
CLI, resolves bind-mount source paths used by nested containers.

The `docker:dind` entrypoint generates the CA, server certificate, and client
certificate automatically at startup. All TLS material appears under
`./state/docker/certs`; no manual certificate command is needed. DinD can
refresh the public certificates when it restarts while retaining their private
keys in that bind mount.

The sandbox mounts only `./state/docker/certs/client`, read-only. That directory
contains `ca.pem`, `cert.pem`, and `key.pem` after the Docker service starts.

Docker selects a compatible storage backend automatically. Keep this checkout
and its `state` directory on a native Linux or WSL filesystem. Merely launching
Compose from WSL is not enough if the checkout remains under `/mnt/c`; that path
is still Windows-backed and is not suitable for the daemon's bind-mounted
`./state/docker/data`.

### 2. Make an SSH agent available

Compose can use any SSH agent that exposes a Unix socket through
`SSH_AUTH_SOCK`. The socket lets the sandbox request signatures; private keys
are not copied into the container.

#### Option A: OpenSSH agent with a manually loaded key

Start the standard agent and add whichever keys should be available to the
sandbox (GitHub keys, etc):

```bash
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/id_ed25519"
ssh-add -L
```

#### Option B: 1Password or another password-manager agent

Enable the SSH agent in the password manager and point `SSH_AUTH_SOCK` at the
Unix socket it provides. For 1Password running on Linux, follow its
[SSH agent setup](https://www.1password.dev/ssh/agent); the default socket is:

```bash
export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"
test -S "$SSH_AUTH_SOCK"
ssh-add -L
```

Eligible keys stored in 1Password are made available to the agent. 1Password will still ask you to approve key use according to its authorization settings.

On Windows, 1Password's official WSL integration runs requests through
Windows `ssh.exe`; it does not expose the WSL Unix socket that this Compose file
must bind-mount into a Linux container. To use the Windows 1Password agent here,
first configure a trusted named-pipe-to-Unix-socket bridge in WSL (commonly
`npiperelay` with `socat`), then export the bridge socket as `SSH_AUTH_SOCK` and
confirm that native WSL `ssh-add -L` succeeds. See 1Password's
[WSL integration documentation](https://www.1password.dev/ssh/integrations/wsl)
for the distinction.

#### Start the stack

After either option reports the expected public key:

```bash
docker compose up -d
```

No state-directory setup is required. Docker creates the missing short-syntax
bind sources automatically. A rootful outer Docker daemon normally creates them
as root; the sandbox entrypoint changes only `./state/home` and
`./state/home/src` to UID/GID `1000:1000` before initializing the home. The
rootful DinD sidecar owns `./state/docker`, so those paths do not need to belong
to the host user. The forwarded agent socket must be accessible to UID `1000`.

Making DinD rootless would not change this behavior because the outer Docker
daemon creates all bind sources before either service starts. This stack keeps
the standard rootful DinD image for the widest Docker build, storage, networking,
and resource-control compatibility; the daemon remains isolated in its own
sidecar and the host Docker socket is not mounted.

The image uses `/ssh-auth.sock` as its canonical internal agent path. To enable
inbound SSH login and outbound SSH-based Git authentication, mount a real host
agent socket at that exact container path. The image can still start without
the mount, but the entrypoint warns and agent-backed SSH functionality remains
unavailable. The supplied Compose configuration requires the host
`SSH_AUTH_SOCK` and mounts it at `/ssh-auth.sock`.

If state from an older image belongs to root, update it once on the Linux host:

```bash
sudo chown -R 1000:1000 state/home
```

To update the image later:

```bash
docker compose pull
docker compose up -d
```

### 3. Trust the SSH host key

Run this command from the same environment and user account as the SSH client:

```bash
ssh -p 2222 sandbox@127.0.0.1
```

Review and accept the fingerprint. Trust is stored for the exact address and
port, so `[127.0.0.1]:2222` and `[localhost]:2222` are different entries.

For Codex Desktop, create an SSH connection for `sandbox@127.0.0.1` on port
`2222` and choose a project under `/home/sandbox/src`.

Use ${EXTERNAL_SSHD_PORT} if you're using a differnt port in place of 2222.

### 4. Sign in to Codex

```bash
docker compose exec sandbox codex login --device-auth
```

The entire sandbox home persists in `./state/home`. On first startup, the
image seeds `./state/home/.codex/config.toml` with
`danger-full-access`, `on-request`, and Auto-review defaults. The container is
the isolation boundary, and an existing config file is never overwritten.
The entrypoint also installs the image's normal `.bash_profile` and `.bashrc`
when those files are missing. Seed files live read-only under `/etc/setup` in
the image; all active files remain at their standard locations under
`/home/sandbox`.

Approval policy and sandbox mode are independent. The default keeps
`approval_policy = "on-request"` while using the container itself as the
isolation boundary. If you later change `sandbox_mode` to `"workspace-write"`
or `"read-only"`, add this to the `sandbox` service so the installed Bubblewrap
can create its nested user and mount namespaces:

```yaml
security_opt:
  - seccomp=unconfined
```

Then recreate the service. This disables Docker's default seccomp filter for
the `sandbox` container, so enable it only when using Codex's inner sandbox.

### 5. Authenticate GitHub CLI

Git repository operations use the forwarded SSH agent. GitHub CLI uses a
separate OAuth token for API operations such as pull requests and issues. Check
the current status first:

```bash
docker compose exec sandbox gh auth status --hostname github.com
```

If it is not authenticated, complete the device flow once:

```bash
docker compose exec sandbox \
  gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key
```

The `--skip-ssh-key` option prevents GitHub CLI from generating or uploading a
key because the forwarded agent already provides it. GitHub CLI keeps its normal
configuration under `~/.config/gh`, persisted at
`./state/home/.config/gh`, so
the OAuth login survives container recreation.

## Using the sandbox

An interactive SSH login starts in `/home/sandbox/src`. The user is `sandbox`
with UID/GID `1000:1000`, and its home directory is `/home/sandbox`.

If configured, verify the forwarded host SSH agent:

```bash
ssh-add -L
```

Install system packages noninteractively with passwordless sudo:

```bash
sudo -n apt-get update
sudo -n apt-get install -y jq
```

Vim is already installed in the image. Additional system packages are part of
the running container and disappear when it is recreated. Add frequently needed
packages to the Dockerfile instead. Projects under `/home/sandbox/src` persist
as part of the sandbox home bind mount. User-level tools and configuration
stored elsewhere under `/home/sandbox` persist as well.

### Nested Docker

The Docker CLI and Compose run in the sandbox, while Docker Engine runs in the
separate `docker` service. The image defaults `DOCKER_HOST`,
`DOCKER_TLS_VERIFY`, and `DOCKER_CERT_PATH` to the sidecar's TLS endpoint and
shared client certificate. Docker commands do not need sudo:

```bash
docker info
docker buildx version
docker compose version
docker run --rm hello-world
```

Nested images, containers, and volumes persist in `./state/docker/data`. The TLS
CA and client credentials persist under `./state/docker/certs`.

### Expose an application for testing

The outer stack reserves `INTERNAL_SERVICE_PORT` (default `3000`) on the Docker
sidecar for a nested application and publishes it on the host as
`EXTERNAL_SERVICE_PORT` (also `3000` by default). The sandbox receives both
values as environment variables.

Make the application listen on `0.0.0.0` inside its container and publish its
container port onto `INTERNAL_SERVICE_PORT`. For an application that listens on
port `8000`:

```bash
docker run --rm -p "$INTERNAL_SERVICE_PORT:8000" your-image
```

The agent can verify the service inside the sandbox at
`http://docker:$INTERNAL_SERVICE_PORT`. The user can open it directly on the
host at:

<http://127.0.0.1:3000>

If `EXTERNAL_SERVICE_PORT` is changed, use that value in the host URL.
Additional nested ports still require SSH forwarding to
`docker:<published-port>` or an explicit outer Compose change.

## Configuration

Set these variables in a `.env` file beside `docker-compose.yml` or export them
before running Compose:

| Variable | Default | Purpose |
| --- | --- | --- |
| `SSH_AUTH_SOCK` | Required by Compose | Host SSH-agent socket mounted at the image's fixed `/ssh-auth.sock` path |
| `EXTERNAL_SSHD_PORT` | `2222` | Host port mapped to the sandbox's SSH port `2222` |
| `INTERNAL_SERVICE_PORT` | `3000` | Port reserved on the Docker sidecar for testing one nested service |
| `EXTERNAL_SERVICE_PORT` | `3000` | Host port mapped to `INTERNAL_SERVICE_PORT` |
| `GIT_CONFIG_USER_NAME` | `Codex Sandbox` | Global Git commit name inside the container |
| `GIT_CONFIG_USER_EMAIL` | Empty | Global Git commit email inside the container |

After changing `EXTERNAL_SSHD_PORT`, `INTERNAL_SERVICE_PORT`, or
`EXTERNAL_SERVICE_PORT`, recreate the stack with `docker compose up -d`. Use the
internal port in the nested container's publish option and the external port in
the host URL.

## Persistent data and security

| Storage | Contents |
| --- | --- |
| `./state/home` | Complete `/home/sandbox`, including projects, Codex state, XDG configuration, GitHub CLI OAuth, and SSH server keys |
| `./state/docker/data` | Nested Docker images, containers, and volumes |
| `./state/docker/certs` | CA, server, and client TLS material for the sidecar daemon |

`docker compose down` preserves these locations. Deleting one removes its
corresponding state. Replacing the SSH host-key directory creates a new
fingerprint that clients must verify before reconnecting.

Treat the complete `./state/home` home, the forwarded SSH agent, and Docker
data as sensitive. The home may contain OAuth tokens or other credentials saved
by CLI tools. Do not share these storage locations between concurrently running
sandbox stacks. Processes in the sandbox can use the forwarded agent while it
is mounted. Anyone with the Docker client certificate can fully control the
privileged sidecar, so protect that volume like a root credential. The host
Docker socket is deliberately not mounted.

## Troubleshooting SSH

Inspect container status and logs:

```bash
docker compose ps
docker compose logs sandbox
```

If the stored SSH key changed, remove only the exact stale host entry and
reconnect:

Windows PowerShell:

```powershell
ssh-keygen -R "[127.0.0.1]:2222" -f "$env:USERPROFILE\.ssh\known_hosts"
ssh -p 2222 sandbox@127.0.0.1
```

Linux or macOS:

```bash
ssh-keygen -R "[127.0.0.1]:2222" -f "$HOME/.ssh/known_hosts"
ssh -p 2222 sandbox@127.0.0.1
```

Use the configured port instead of `2222` when `EXTERNAL_SSHD_PORT` is
overridden.

## Troubleshooting Docker

Check both services and verify the TLS connection from the sandbox:

```bash
docker compose ps
docker compose logs docker
docker compose exec sandbox docker info
```

If the daemon is healthy but a nested bind mount is empty or missing, confirm
the same host workspace is mounted at `/home/sandbox/src` in both services.

## Developer information

The repository Compose file builds the local Dockerfile and uses bind-mounted
state and workspace directories. With either SSH-agent option from the quick
start active:

```bash
ssh-add -L
docker compose up --build -d
```

Important implementation files:

- `Dockerfile`: installs Codex, `uv`, a uv-managed Python 3.12, OpenSSH, the Docker CLI, Git, sudo, Vim, and bubblewrap, plus the current stable GitHub CLI from GitHub's official apt repository
- `docker-compose.yml`: runs the privileged Docker daemon sidecar and shares its TLS client credentials
- `docker-entrypoint.sh`: initializes an empty persistent home, configures Git, and then replaces itself with SSH
- `sshd_config.conf`: limits key-only login to `sandbox` and permits agent and TCP forwarding
- `agent-authorized-keys`: obtains accepted login keys from the forwarded agent
- `agents/AGENTS.md`: supplies container-specific guidance to Codex
- `codex-config.toml`: supplies the initial user-level Codex defaults
- `/etc/setup` in the image: holds read-only shell, Codex, and agent-guidance seed files used at their normal home-directory locations only when absent

The apt installation steps use locked BuildKit cache mounts for repository metadata and
downloaded packages. These caches speed up later builds without becoming part
of the image; they are local to the builder and may be removed by BuildKit's
garbage collection.

Validate Compose and the image with:

```bash
docker compose config --quiet
docker compose up --build --wait
docker compose exec sandbox docker run --rm hello-world
```

The GitHub Actions workflow publishes `main` and version tags to Docker Hub and
signs published images with Cosign.
