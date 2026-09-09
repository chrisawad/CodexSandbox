# syntax=docker/dockerfile:1

FROM node:22-trixie-slim

# Retain apt downloads in locked BuildKit caches as recommended by Docker:
# https://docs.docker.com/reference/dockerfile/#example-cache-apt-packages
RUN --mount=type=cache,id=codex-sandbox-apt-packages,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=codex-sandbox-apt-metadata,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf '%s\n' \
        'Binary::apt::APT::Keep-Downloaded-Packages "true";' \
        >/etc/apt/apt.conf.d/keep-cache \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
    && install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d \
    && wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
        "$(dpkg --print-architecture)" \
        >/etc/apt/sources.list.d/github-cli.list

RUN --mount=type=cache,id=codex-sandbox-apt-packages,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=codex-sandbox-apt-metadata,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bubblewrap \
        docker-buildx \
        docker-cli \
        docker-compose \
        gh \
        git \
        openssh-server \
        sudo \
        vim \
    && gh --version \
    && docker --version \
    && docker buildx version \
    && docker compose version

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    UV_PYTHON_BIN_DIR=/usr/local/bin

RUN uv python install 3.12 --default \
    && uv --version \
    && python --version \
    && python3 --version \
    && python3.12 --version

RUN npm install --global @openai/codex@latest \
    && npm cache clean --force \
    && codex --version

RUN rm -f /etc/ssh/ssh_host_* \
    && groupmod --new-name sandbox node \
    && usermod --login sandbox --home /home/sandbox --move-home --shell /bin/bash node \
    && passwd --delete sandbox \
    && printf '%s\n' 'sandbox ALL=(ALL:ALL) NOPASSWD: ALL' >/etc/sudoers.d/sandbox \
    && chmod 0440 /etc/sudoers.d/sandbox \
    && /usr/sbin/visudo --check --file=/etc/sudoers.d/sandbox \
    && install -d -m 0755 /run/host-services /run/sshd \
    && install -D -m 0644 /home/sandbox/.bashrc /etc/setup/bashrc \
    && su --shell /bin/sh --command 'sudo -n true' sandbox

# SSH_AUTH_SOCK contains only a Unix socket path, never key material.
ENV HOME=/home/sandbox \
    SSH_AUTH_SOCK=/ssh-auth.sock \
    DOCKER_HOST=tcp://docker:2376 \
    DOCKER_TLS_VERIFY=1 \
    DOCKER_CERT_PATH=/certs/client \
    INTERNAL_SERVICE_PORT=3000 \
    EXTERNAL_SERVICE_PORT=3000

COPY sshd_config.conf /etc/ssh/sshd_config.d/99-container.conf
COPY --chmod=0644 agents/AGENTS.md /etc/setup/AGENTS.md
COPY --chmod=0644 codex-config.toml /etc/setup/codex-config.toml
COPY --chmod=0644 bash_profile /etc/setup/bash_profile
COPY --chmod=0755 agent-authorized-keys /usr/local/bin/agent-authorized-keys
COPY --chmod=0755 docker-entrypoint.sh /docker-entrypoint.sh

EXPOSE 2222

STOPSIGNAL SIGTERM

WORKDIR /home/sandbox

USER sandbox

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD docker info >/dev/null && /usr/sbin/sshd -t && kill -0 "$(cat /home/sandbox/.cache/sshd.pid)"

ENTRYPOINT ["/docker-entrypoint.sh"]
