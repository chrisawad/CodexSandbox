# Agent container environment instructions

These instructions apply to all work in this container.

## Runtime

- You are working as the `sandbox` user with UID/GID `1000:1000` inside a Docker
  container sandbox.
- The home directory is `/home/sandbox`. Interactive SSH login shells change into
  `/home/sandbox/src` after login; that is the working directory, not the home
  directory.
- The container is created and managed by an external `docker-compose.yml`.
- A private Docker daemon runs in a separate sidecar container. `docker`,
  `docker buildx`, and `docker compose` connect to it over TLS using the
  preconfigured `DOCKER_HOST`, `DOCKER_TLS_VERIFY`, and `DOCKER_CERT_PATH`
  environment variables. Docker commands do not need `sudo`.
- Treat the Docker daemon, host Docker daemon, outer Compose lifecycle, port
  publishing, and outer volume configuration as external infrastructure. Do not
  try to start `dockerd`, and do not assume the outer Compose file is available
  inside this container.

## GitHub authentication

- When a host SSH agent is available, use SSH URLs for GitHub repositories so
  Git authenticates through the forwarded `SSH_AUTH_SOCK`. Verify it with
  `ssh-add -L` before relying on it.
- If the agent is unavailable or has no identities, tell the user that the host
  agent must be loaded and mounted. Never create, copy, or store a private SSH
  key in this container.
- Before using GitHub CLI features, check `gh auth status --hostname github.com`.
  If GitHub CLI is not authenticated, run
  `gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key` and ask
  the user to complete the one-time browser/device authorization.
- The `--skip-ssh-key` option is intentional: the host's forwarded SSH agent
  supplies the existing Git key, while GitHub CLI stores its separate OAuth
  credential under the persistent `~/.config/gh` directory.
- Do not configure GitHub CLI as an HTTPS Git credential helper unless the user
  explicitly asks to use HTTPS. Never print or expose the stored OAuth token.

## Tool installation

- Inspect the available toolchain before starting project work.
- If a required tool or dependency is missing, tell the user exactly what needs
  to be installed, why it is required, and whether the installation is
  system-wide or project-local.
- Ask the user for explicit permission before installing any missing tool.
- After the user approves, install the required tool and continue the original
  task without waiting for another instruction.
- The `sandbox` user has passwordless `sudo`. Use `sudo -n` for noninteractive
  system package installation and configuration.
- `uv` and a uv-managed Python 3.12 are installed system-wide. Use `uv` for
  project environments and Python dependency management when appropriate.
- Prefer project-local dependencies over global or system-wide installations
  when practical.
- Files installed anywhere under `/home/sandbox` survive a container recreate.
  System packages and files written outside the home directory may be lost.

## Docker-based builds and verification

- Prefer a project's existing Dockerfile and Compose configuration when they are
  available.
- Use the private sidecar Docker daemon for isolated builds, tests, and
  application verification. Do not mount or attempt to control the host Docker
  socket.
- The workspace is mounted at `/home/sandbox/src` in both containers so bind
  mounts below that path work when the remote daemon resolves them.
- `INTERNAL_SERVICE_PORT` is the dedicated port to publish from a nested
  container onto the Docker sidecar. `EXTERNAL_SERVICE_PORT` is the host-facing
  port mapped to it by the outer stack.
- To expose a nested application, make it listen on `0.0.0.0` and publish its
  container port onto the sidecar's `INTERNAL_SERVICE_PORT`, for example
  `docker run -p "$INTERNAL_SERVICE_PORT:<container-port>" ...`. Validate the
  service at `docker:$INTERNAL_SERVICE_PORT` from this container, then tell the
  user to open `http://127.0.0.1:$EXTERNAL_SERVICE_PORT` (or the appropriate
  protocol).
- Other ports published by nested containers are not automatically published
  through the outer stack. Use SSH TCP forwarding to `docker:<published-port>`
  when an additional port is necessary, and state the exact forwarded port.
- Never claim that a nested application is reachable from the host until that
  path has been verified.
