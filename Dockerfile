FROM node:22-bookworm-slim AS codex-installer

RUN npm install --global @openai/codex@latest \
    && npm cache clean --force

FROM nginx:latest

ENV NGINX_SSL_CERTIFICATE=/etc/nginx/ssl/nginx-selfsigned.crt \
    NGINX_SSL_CERTIFICATE_KEY=/etc/nginx/ssl/nginx-selfsigned.key \
    NGINX_WEB_ROOT=/usr/share/nginx/html \
    NGINX_HOST_HTTP_PORT=8080 \
    NGINX_HOST_HTTPS_PORT=4443 \
    NGINX_ENVSUBST_FILTER=^NGINX_

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bubblewrap \
        gh \
        git \
        nodejs \
        openssh-server \
        openssl \
        util-linux \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_* \
    && groupadd --gid 1000 codex \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash codex \
    && mkdir -p /run/sshd /home/codex/.ssh /home/codex/.codex /home/codex/src /etc/ssh/host-keys /etc/nginx/ssl \
    && chmod 0700 /home/codex/.ssh /home/codex/.codex \
    && chown -R codex:codex /home/codex "${NGINX_WEB_ROOT}" \
    && openssl req -x509 -nodes -newkey rsa:2048 -sha256 -days 3650 \
        -keyout "${NGINX_SSL_CERTIFICATE_KEY}" \
        -out "${NGINX_SSL_CERTIFICATE}" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    && chmod 0600 "${NGINX_SSL_CERTIFICATE_KEY}" \
    && chmod 0644 "${NGINX_SSL_CERTIFICATE}"

COPY sshd_config.conf /etc/ssh/sshd_config.d/99-container.conf
COPY default.conf.template /etc/nginx/templates/default.conf.template
# COPY --chown=1000:1000 --chmod=0600 codex-config.toml /home/codex/.codex/config.toml
COPY --chown=1000:1000 agents/AGENTS.md agents/HOSTING.md /home/codex/src/
COPY --chown=1000:1000 --chmod=0644 bash_profile /home/codex/.bash_profile
COPY agent-authorized-keys /usr/local/bin/agent-authorized-keys
COPY docker-entrypoint.sh /usr/local/bin/nginx-ssh-entrypoint
COPY --from=codex-installer /usr/local/lib/node_modules/@openai/codex /usr/local/lib/node_modules/@openai/codex

RUN ln -s ../lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex \
    && chmod 0755 /usr/local/bin/agent-authorized-keys /usr/local/bin/nginx-ssh-entrypoint \
    && codex --version

EXPOSE 22 80 443

STOPSIGNAL SIGTERM

WORKDIR /home/codex/src

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD nginx -t && /usr/sbin/sshd -t && kill -0 "$(cat /run/sshd.pid)"

ENTRYPOINT ["/usr/local/bin/nginx-ssh-entrypoint"]
