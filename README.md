# Codex Sandbox

`cawad/codex-sandbox` is a ready-to-run Docker image that provides:

- Codex CLI in a persistent Linux workspace
- key-only SSH access for Codex Desktop or another SSH client
- a forwarded host SSH agent for GitHub and other outbound SSH connections
- nginx for serving applications over HTTP and HTTPS

Links: [Docker Hub](https://hub.docker.com/r/cawad/codex-sandbox) [GitHub](https://github.com/chrisawad/CodexSandbox)

## Quick start with Docker Compose

You need Docker with the Compose plugin, an SSH key, and a running SSH agent.
Run Docker Compose from the environment that provides the Unix
`SSH_AUTH_SOCK`, such as Linux, macOS, or WSL.

### 1. Create `docker-compose.yml`

```yaml
services:
  sandbox:
    image: cawad/codex-sandbox:latest
    container_name: nginx-ssh
    restart: unless-stopped
    security_opt:
      - seccomp=unconfined
    ports:
      - "127.0.0.1:${NGINX_HOST_HTTP_PORT:-8080}:80"
      - "127.0.0.1:${NGINX_HOST_HTTPS_PORT:-4443}:443"
      - "127.0.0.1:${SSHD_PORT:-2222}:22"
    environment:
      NGINX_HOST_HTTP_PORT: "${NGINX_HOST_HTTP_PORT:-8080}"
      NGINX_HOST_HTTPS_PORT: "${NGINX_HOST_HTTPS_PORT:-4443}"
      GIT_CONFIG_USER_NAME: "${GIT_CONFIG_USER_NAME:-Codex Sandbox}"
      GIT_CONFIG_USER_EMAIL: "${GIT_CONFIG_USER_EMAIL:-}"
    volumes:
      - ${SSH_AUTH_SOCK}:/run/host-services/ssh-auth.sock
      - ./states/codex:/root/.codex
      - ./states/ssh-host-keys:/etc/ssh/host-keys
      - ./states/workspaces:/workspaces
```

The loopback-only port bindings keep SSH and nginx accessible from the host
without exposing them to the local network.

### 2. Load an SSH key and start the container

If you do not already have a running SSH agent, start one and load the key that
you want to use for both container login and outbound SSH connections:

```bash
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/id_ed25519"
docker compose up -d
```

Compose pulls `cawad/codex-sandbox:latest` from Docker Hub the first time it
starts the service. To update later, run:

```bash
docker compose pull
docker compose up -d
```

### 3. Trust the SSH host key on first connection

Run this command from the same operating environment and user account that
will run the SSH client:

```bash
ssh -p 2222 root@127.0.0.1
```

Review and accept the host-key prompt. OpenSSH saves trust for the exact
`[127.0.0.1]:2222` destination. If Codex Desktop is running on Windows, run
the command in Windows PowerShell. Running it in WSL updates WSL's separate
`known_hosts` file and does not establish trust for the Windows app.

Use `127.0.0.1` instead of `localhost`. Depending on the host configuration,
`localhost` may resolve to the IPv6 loopback address `::1`; this container's
recommended host connection uses the IPv4 loopback address, so that IPv6
connection fails.

Use the value of `SSHD_PORT` instead of `2222` if you changed the default.

### 4. Authenticate Codex

Give this deployment its own Codex login:

```bash
docker exec -it nginx-ssh codex login --device-auth
```

The login is saved in the persistent `./states/codex` directory.

### 5. Connect Codex Desktop

In Codex Desktop, open **Settings > Connections**, add a connection for
`127.0.0.1:2222`, and select a project under `/workspaces`.

## Using the container

An interactive SSH login starts in `/workspaces`. The
`./states/workspaces` directory keeps projects across container updates and
recreations. Codex is available as:

```bash
codex
```

The forwarded host agent is available inside SSH sessions. Verify it with:

```bash
ssh-add -L
```

Root keeps its normal home directory at `/root`. Codex state is stored in
`/root/.codex`, separately from project files.

### Nginx endpoints

The default host endpoints are:

- HTTP: <http://127.0.0.1:8080>
- HTTPS: <https://127.0.0.1:4443>
- SSH: `127.0.0.1:2222`

Nginx serves `/usr/share/nginx/html`. The container includes guidance that
directs Codex to publish built static applications there and report the
externally mapped ports. The default HTTPS certificate is self-signed, so a
browser will display a trust warning.

## Configuration

Set these variables in a `.env` file beside `docker-compose.yml` or export them
before running Compose:

| Variable | Default | Purpose |
| --- | --- | --- |
| `SSHD_PORT` | `2222` | Host port for SSH |
| `NGINX_HOST_HTTP_PORT` | `8080` | Host port for nginx HTTP |
| `NGINX_HOST_HTTPS_PORT` | `4443` | Host port for nginx HTTPS |
| `GIT_CONFIG_USER_NAME` | `Codex Sandbox` | Global Git commit name in the container |
| `GIT_CONFIG_USER_EMAIL` | Empty | Global Git commit email in the container |

For example:

```dotenv
SSHD_PORT=2223
NGINX_HOST_HTTP_PORT=9080
NGINX_HOST_HTTPS_PORT=9443
GIT_CONFIG_USER_NAME=Your Name
GIT_CONFIG_USER_EMAIL=you@example.com
```

After changing ports, recreate the service with `docker compose up -d` and use
the new SSH port in both the first-connect command and SSH config.

### Custom TLS certificate or web content

The image supports these additional container environment variables:

| Variable | Default |
| --- | --- |
| `NGINX_SSL_CERTIFICATE` | `/etc/nginx/ssl/nginx-selfsigned.crt` |
| `NGINX_SSL_CERTIFICATE_KEY` | `/etc/nginx/ssl/nginx-selfsigned.key` |
| `NGINX_WEB_ROOT` | `/usr/share/nginx/html` |

Add the variables and read-only mounts to the `sandbox` service:

```yaml
environment:
  NGINX_SSL_CERTIFICATE: /etc/nginx/ssl/custom.crt
  NGINX_SSL_CERTIFICATE_KEY: /etc/nginx/ssl/custom.key
  NGINX_WEB_ROOT: /srv/www
volumes:
  - ./certs/server.crt:/etc/nginx/ssl/custom.crt:ro
  - ./certs/server.key:/etc/nginx/ssl/custom.key:ro
  - ./html:/srv/www:ro
```

Use a certificate issued for the hostname through which users will access
nginx. The bundled self-signed certificate is intended only as a working
default.

## Persistent data and security

| Host path | Contents |
| --- | --- |
| `./states/codex` | Codex login, configuration, and local state |
| `./states/ssh-host-keys` | Private SSH server keys that preserve the server fingerprint |
| `./states/workspaces` | Projects and working files |

`docker compose down` preserves these bind-mounted directories. Deleting them
removes the corresponding projects, Codex login, or SSH server identity.
Replacing `./states/ssh-host-keys` creates a new fingerprint that clients must
verify before reconnecting.

Treat the Codex state and SSH host-key directories as secrets. Do not copy them
into an image, source repository, or shared directory. Do not share one Codex
state directory between concurrently running containers.

SSH password authentication is disabled. Login keys are obtained from the
mounted SSH agent, so the image does not need an `authorized_keys` file or a
copy of a private client key.

## Troubleshooting

### Host-key or hostname verification fails

Trust the exact IP address and port from the environment running Codex Desktop:

```bash
ssh -p 2222 root@127.0.0.1
```

If the persisted server identity was intentionally replaced, verify the new
fingerprint, remove the old entry from the same operating environment that
runs the SSH client, and connect again.

On Windows, run these commands in PowerShell:

```powershell
ssh-keygen -R "[127.0.0.1]:2222" -f "$env:USERPROFILE\.ssh\known_hosts"
ssh -p 2222 root@127.0.0.1
```

On Linux or macOS, run:

```bash
ssh-keygen -R "[127.0.0.1]:2222" -f "$HOME/.ssh/known_hosts"
ssh -p 2222 root@127.0.0.1
```

Do not remove a changed host key until you have confirmed why it changed.
Use the configured `SSHD_PORT` in place of `2222` when the default port is
overridden.

### Compose reports that the SSH agent mount is invalid

`SSH_AUTH_SOCK` is unset or points to an unavailable socket. Start an agent,
load a key, and confirm the variable before starting Compose:

```bash
ssh-add -L
printf '%s\n' "$SSH_AUTH_SOCK"
```

### SSH reports `Permission denied (publickey)`

Confirm the host agent contains the public key that the client is offering:

```bash
ssh-add -L
ssh -v -p 2222 root@127.0.0.1
```

### HTTPS displays a certificate warning

This is expected with the bundled self-signed certificate. Use HTTP for local
testing or mount a trusted certificate issued for the hostname you use.

## Developer information

The following information is for contributors building or publishing the
image, rather than users running it from Docker Hub.

### Build the repository checkout

The repository's `docker-compose.yml` builds the local Dockerfile, pulls the
current `nginx:latest` base, and uses bind-mounted state and workspace
directories:

```bash
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/id_ed25519"
docker compose up --build -d
```

Important implementation files include:

- `Dockerfile`: installs OpenSSH, Codex, GitHub CLI, Git, and bubblewrap on nginx
- `docker-entrypoint.sh`: configures Git, creates persistent SSH host keys, and starts SSH plus nginx
- `sshd_config.conf`: enforces key-only root login and agent-backed authorized keys
- `default.conf.template`: configures nginx HTTP, HTTPS, and the web root
- `agents/`: instructions installed into `/workspaces`

Codex uses bubblewrap on Linux. The service sets
`security_opt: seccomp=unconfined` so bubblewrap can create nested user and
mount namespaces inside Docker. The container remains non-privileged and does
not receive `SYS_ADMIN`.

Validate Compose and the image with:

```bash
docker compose config
docker build --pull -t cawad/codex-sandbox:latest .
```

### Publish to Docker Hub

For a manual publication:

```bash
docker login
docker build --pull -t cawad/codex-sandbox:latest .
docker push cawad/codex-sandbox:latest
```

The GitHub Actions workflow in `.github/workflows/docker-publish.yml` publishes:

- `cawad/codex-sandbox:main` when changes reach `main`
- the matching version and `latest` for tags such as `v1.2.3`

Published images are signed through Sigstore using GitHub's OpenID Connect
identity. The workflow requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`
repository secrets. Each deployment generates its SSH host keys at runtime;
private or reusable host keys are never stored in the published image.
