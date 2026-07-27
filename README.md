# Nginx + SSH

An `nginx:latest`-based HTTP/HTTPS image with OpenSSH server access for `root`.
SSH is key-only: password authentication is disabled.

The Compose configuration also mounts the host's SSH agent socket into the
container. This lets commands run in the SSH session authenticate to services
such as GitHub without copying private keys into the image or container.

## Run with Docker Compose

Start an agent and load the key you want to use for both login and outbound
connections:

```bash
eval "$(ssh-agent -s)"
ssh-add "$HOME/.ssh/id_ed25519"
docker compose up --build -d
```

The Compose build is configured to pull the current `nginx:latest` base before
building.

The container's SSH server identity is persisted in
`./state/ssh-host-keys`. Compose creates this host directory when needed, and
the entrypoint generates any missing keys there on first startup. Rebuilding or
recreating the container therefore preserves its SSH fingerprints.

No `authorized_keys` file is required. OpenSSH obtains its allowed public keys
from the mounted agent, so any identity shown by `ssh-add -L` can log in.

Connect as `root`:

```bash
ssh -p 2222 root@localhost
```

If another system will connect over SSH non-interactively and relies on
`known_hosts` for server trust, connect to the container manually once first.
Review and accept the SSH host-key prompt so the key is saved in the same
user account and operating environment that will run the non-interactive
connection. For example, before Codex for Windows connects to the container
non-interactively, use Windows OpenSSH to connect manually once and accept the
host key. Connecting from WSL instead would update WSL's separate
`known_hosts` and would not establish trust for Codex for Windows.

Root keeps its standard home directory at `/root`. Interactive SSH sessions
change into `/workspaces` through root's login profile. The Codex CLI is
preinstalled and available as `codex`.

`/workspaces/AGENTS.md` and `/workspaces/HOSTING.md` describe the container
environment, require Codex to report the externally published nginx ports
from `NGINX_HOST_HTTP_PORT` and `NGINX_HOST_HTTPS_PORT`, and direct built
application distributions to nginx's configured web root.

Codex uses its default state directory for the root user, `/root/.codex`, which
keeps its state outside `/workspaces`. Compose persists that directory in
`./state/codex`, giving this deployment its own credential cache instead of
sharing the host's rotating refresh token. The image does not set
`CODEX_HOME` or install a custom `config.toml`.

After the first startup, authenticate this deployment independently:

```bash
docker exec -it nginx-ssh codex login --device-auth
```

The resulting `./state/codex/auth.json` contains access tokens and must be
treated like a password. The directory is excluded from Git and the Docker
build context. Do not share the same Codex state directory between concurrently
running containers. Its default permission profile limits sandboxed commands
to the active workspace and minimal runtime paths, but the state mount itself
is not a credential-isolation boundary.

Codex uses bubblewrap to sandbox commands on Linux. The Compose service sets
`security_opt: seccomp=unconfined` so bubblewrap can create its nested user and
mount namespaces inside Docker. The container itself remains non-privileged and
does not receive `SYS_ADMIN`.

From inside that SSH session, verify access to the host agent:

```bash
ssh-add -L
```

To expose local projects at the login directory, uncomment the workspace mount
in `docker-compose.yml`:

```yaml
volumes:
  - ./workspaces:/workspaces
```

Keep `./state/ssh-host-keys` private. It contains the server's private host
keys, is excluded from Git and the Docker build context, and should not be
copied into a published image. Deleting this directory causes new fingerprints
to be generated the next time the container starts.

By default, nginx is available at <http://127.0.0.1:8080> and
<https://127.0.0.1:4443>. Override the published ports when starting Compose:

```bash
NGINX_HOST_HTTP_PORT=9080 NGINX_HOST_HTTPS_PORT=9443 \
  docker compose up --build -d
```

Compose passes the resolved values into the container so Codex can report the
correct external URLs. Using the IPv4 address avoids delays caused by
`localhost` resolving to IPv6. The HTTPS endpoint uses the image's self-signed
certificate by default, so clients will display a trust warning.

## Configure Git identity

Compose configures Git's global commit identity from these variables:

| Variable | Default |
| --- | --- |
| `GIT_CONFIG_USER_NAME` | `Codex Sandbox` |
| `GIT_CONFIG_USER_EMAIL` | Empty |

Set the email before starting the container if commits should use a specific
address:

```bash
GIT_CONFIG_USER_EMAIL=you@example.com docker compose up --build -d
```

These values configure commit attribution only. Git authentication continues
to use the forwarded SSH agent.

## Override TLS certificates or web content

The nginx configuration reads these environment variables:

| Variable | Default |
| --- | --- |
| `NGINX_HOST_HTTP_PORT` | `8080` |
| `NGINX_HOST_HTTPS_PORT` | `4443` |
| `NGINX_SSL_CERTIFICATE` | `/etc/nginx/ssl/nginx-selfsigned.crt` |
| `NGINX_SSL_CERTIFICATE_KEY` | `/etc/nginx/ssl/nginx-selfsigned.key` |
| `NGINX_WEB_ROOT` | `/usr/share/nginx/html` |

Commented examples are included in `docker-compose.yml`. To use your own
certificate and site content, uncomment the corresponding environment values
and short-syntax read-only mounts:

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

Use a certificate issued for your public hostname when deploying publicly.
The bundled self-signed certificate is intended only as a working default.

## Run without Compose

```bash
docker build -t cawad/codex-sandbox:latest .
docker run --rm \
  --name nginx-ssh \
  -p 8080:80 \
  -p 4443:443 \
  -p 2222:22 \
  -e NGINX_HOST_HTTP_PORT=8080 \
  -e NGINX_HOST_HTTPS_PORT=4443 \
  -v "$SSH_AUTH_SOCK:/run/host-services/ssh-auth.sock" \
  -v "./state/codex:/root/.codex:rw" \
  -v "./state/ssh-host-keys:/etc/ssh/host-keys:rw" \
  cawad/codex-sandbox:latest
```

The entrypoint does not copy, validate, or modify SSH login keys. OpenSSH asks
the mounted agent for its public-key list when authenticating a login.

## Publish to Docker Hub

The image repository is `cawad/codex-sandbox`:

```bash
docker login
docker build --pull -t cawad/codex-sandbox:latest .
docker push cawad/codex-sandbox:latest
```

The GitHub Actions workflow in `.github/workflows/docker-publish.yml`
automatically builds and pushes the image:

- A push to `main`, including a pull request merge, publishes
  `cawad/codex-sandbox:main`.
- A pushed tag matching `v*.*.*` publishes the version tag and `latest`, such
  as `cawad/codex-sandbox:v1.2.3` and `cawad/codex-sandbox:latest`.

Published images are signed through Sigstore using GitHub's OpenID Connect
identity.

Configure these GitHub Actions repository secrets before running the workflow:

| Secret | Value |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub username with push access to the repository |
| `DOCKERHUB_TOKEN` | Docker Hub access token with read/write permission |

Each deployment generates its own SSH host keys in the mounted host directory
on first startup. No private keys or reusable SSH host keys are stored in the
published image.
