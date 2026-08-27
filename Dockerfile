FROM node:22-bookworm-slim AS codex-installer

RUN npm install --global @openai/codex@latest \
    && npm cache clean --force

FROM nginx:latest

ENV NGINX_SSL_CERTIFICATE=/etc/nginx/ssl/nginx-selfsigned.crt \
    NGINX_SSL_CERTIFICATE_KEY=/etc/nginx/ssl/nginx-selfsigned.key \
    NGINX_WEB_ROOT=/usr/share/nginx/html \
    NGINX_HOST_HTTP_PORT=8080 \
    NGINX_HOST_HTTPS_PORT=4443 \
    NGINX_ENVSUBST_FILTER=^NGINX_ \
    HOME=/home/sandbox

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bubblewrap \
        gh \
        git \
        nodejs \
        openssh-server \
        openssl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_* \
    && groupadd --gid 1000 sandbox \
    && useradd --uid 1000 --gid 1000 --home-dir /home/sandbox --create-home --shell /bin/bash sandbox \
    && passwd --delete sandbox \
    && mkdir -p /run/host-services /home/sandbox/.cache/nginx /home/sandbox/.ssh/host-keys /home/sandbox/.codex /home/sandbox/src /etc/codex /etc/nginx/ssl \
    && chmod 0700 /home/sandbox/.ssh /home/sandbox/.ssh/host-keys /home/sandbox/.codex \
    && openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 \
        -keyout "${NGINX_SSL_CERTIFICATE_KEY}" \
        -out "${NGINX_SSL_CERTIFICATE}" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    && chmod 0600 "${NGINX_SSL_CERTIFICATE_KEY}" \
    && chmod 0644 "${NGINX_SSL_CERTIFICATE}" \
    && rm -f /etc/nginx/conf.d/default.conf \
    && sed -i \
        -e 's/^user  nginx;/# The container runtime selects the non-root user./' \
        -e 's#^pid        /run/nginx.pid;#pid        /home/sandbox/.cache/nginx/nginx.pid;#' \
        /etc/nginx/nginx.conf \
    && chown -R sandbox:sandbox \
        /run/host-services \
        /home/sandbox \
        /etc/nginx/conf.d \
        /etc/nginx/ssl \
        /var/cache/nginx \
        "${NGINX_WEB_ROOT}"

COPY sshd_config.conf /etc/ssh/sshd_config.d/99-container.conf
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY agents/AGENTS.md agents/HOSTING.md /etc/codex/
# COPY --chown=1000:1000 --chmod=0600 codex-config.toml /home/sandbox/.codex/config.toml
COPY --chown=1000:1000 --chmod=0644 bash_profile /home/sandbox/.bash_profile
COPY agent-authorized-keys /usr/local/bin/agent-authorized-keys
COPY docker-entrypoint.sh /usr/local/bin/nginx-ssh-entrypoint
COPY --from=codex-installer /usr/local/lib/node_modules/@openai/codex /usr/local/lib/node_modules/@openai/codex

RUN ln -s ../lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex \
    && ln -s /etc/codex/AGENTS.md /home/sandbox/.codex/AGENTS.md \
    && chown -h sandbox:sandbox /home/sandbox/.codex/AGENTS.md \
    && chmod 0755 /usr/local/bin/agent-authorized-keys /usr/local/bin/nginx-ssh-entrypoint \
    && codex --version

EXPOSE 2222 8080 4443

STOPSIGNAL SIGTERM

WORKDIR /home/sandbox/src

USER sandbox:sandbox

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD nginx -t && /usr/sbin/sshd -t && kill -0 "$(cat /home/sandbox/.cache/sshd.pid)" && kill -0 "$(cat /home/sandbox/.cache/nginx/nginx.pid)"

ENTRYPOINT ["/usr/local/bin/nginx-ssh-entrypoint"]
