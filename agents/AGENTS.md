# Agent container environment instructions

These instructions apply to all work under `/workspaces`.

## Runtime

- You are working as `root` inside a Docker container sandbox.
- Root's home directory is `/root`. Interactive SSH login shells change into
  `/workspaces` after login; `/workspaces` is the working directory, not the
  home directory.
- The container is created and managed by an external `docker-compose.yml`.
- Treat the host, Docker daemon, Compose lifecycle, port publishing, and volume
  configuration as external infrastructure. Do not assume the Compose file is
  available inside the container.
- Nginx is already running in the container. Do not start a replacement web
  server for application testing when the application can be built and served
  as static files.

## Tool installation

- Inspect the available toolchain before starting project work.
- If a required tool or dependency is missing, tell the user exactly what needs
  to be installed, why it is required, and whether the installation is
  system-wide or project-local.
- Ask the user for explicit permission before installing any missing tool.
- After the user approves, install the required tool and continue the original
  task without waiting for another instruction.
- Prefer project-local dependencies over global or system-wide installations
  when practical.
- Explain that tools installed in /workspaces will survive a container recreate, but anything installed elsewhere may be lost if the container is recreated.

## User-facing ports

- Nginx HTTP listens on port `80` inside the container. Its externally
  published host port is stored in `NGINX_HOST_HTTP_PORT` and defaults to
  `8080`.
- Nginx HTTPS listens on port `443` inside the container. Its externally
  published host port is stored in `NGINX_HOST_HTTPS_PORT` and defaults to
  `4443`.
- Before giving the user a URL, read the current values from the environment.
  Do not assume the defaults:

  ```bash
  http_port="${NGINX_HOST_HTTP_PORT:-8080}"
  https_port="${NGINX_HOST_HTTPS_PORT:-4443}"
  ```

- Always construct user-facing URLs as
  `http://127.0.0.1:${NGINX_HOST_HTTP_PORT}` and
  `https://127.0.0.1:${NGINX_HOST_HTTPS_PORT}`, using the resolved values
  rather than printing the variable names literally.
- Use `127.0.0.1`, not `localhost`, in user-facing links to avoid IPv6
  resolution and connection delays.
- Never tell the user to open container ports `80` or `443`. Those ports are
  valid only for checks performed from inside the container.

## Hosting applications

- When serving an application for testing, build its production distribution
  and publish that distribution through nginx.
- Copy the built distribution into the directory identified by
  `NGINX_WEB_ROOT`. Its default value is `/usr/share/nginx/html`.
- Do not direct the user to a framework development-server port. Report the
  nginx host URLs using the current `NGINX_HOST_HTTP_PORT` and
  `NGINX_HOST_HTTPS_PORT` values.
- Read `/workspaces/HOSTING.md` for the publishing and validation workflow.
