#!/bin/bash
set -Eeuo pipefail

declare -a service_pids=()

cleanup() {
    local status=$?

    trap - EXIT INT TERM QUIT

    if ((${#service_pids[@]})); then
        kill -TERM "${service_pids[@]}" 2>/dev/null || true
        wait "${service_pids[@]}" 2>/dev/null || true
    fi

    exit "$status"
}

trap cleanup EXIT INT TERM QUIT

readonly ssh_host_key_dir=/home/sandbox/.ssh/host-keys
readonly sandbox_home=/home/sandbox
readonly source_dir=/home/sandbox/src

: "${NGINX_HOST_HTTP_PORT:=8080}"
: "${NGINX_HOST_HTTPS_PORT:=4443}"
: "${GIT_CONFIG_USER_NAME:=Codex Sandbox}"
: "${GIT_CONFIG_USER_EMAIL:=}"

validate_host_port() {
    local variable_name=$1
    local port=$2

    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
        printf 'Invalid %s: %q. Expected an integer from 1 through 65535.\n' \
            "$variable_name" "$port" >&2
        exit 1
    fi
}

validate_host_port NGINX_HOST_HTTP_PORT "$NGINX_HOST_HTTP_PORT"
validate_host_port NGINX_HOST_HTTPS_PORT "$NGINX_HOST_HTTPS_PORT"

install -d -m 0700 "$sandbox_home/.codex" "$ssh_host_key_dir"
install -d -m 0755 "$sandbox_home/.cache/nginx" "$source_dir"

if [[ ! -e "$sandbox_home/.codex/AGENTS.md" && ! -L "$sandbox_home/.codex/AGENTS.md" ]]; then
    ln -s /etc/codex/AGENTS.md "$sandbox_home/.codex/AGENTS.md"
fi

git config --global user.name "$GIT_CONFIG_USER_NAME"

if [[ -n "$GIT_CONFIG_USER_EMAIL" ]]; then
    git config --global user.email "$GIT_CONFIG_USER_EMAIL"
fi

readonly ssh_session_environment="SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock NGINX_HOST_HTTP_PORT=$NGINX_HOST_HTTP_PORT NGINX_HOST_HTTPS_PORT=$NGINX_HOST_HTTPS_PORT"

generate_host_key() {
    local key_type=$1
    local key_path=$2
    shift 2

    if [[ ! -s "$key_path" ]]; then
        rm -f "$key_path" "${key_path}.pub"
        ssh-keygen -q -t "$key_type" "$@" -N '' -f "$key_path"
    elif [[ ! -s "${key_path}.pub" ]]; then
        ssh-keygen -y -f "$key_path" >"${key_path}.pub"
    fi

    chmod 0600 "$key_path"
    chmod 0644 "${key_path}.pub"
}

generate_host_key ed25519 "$ssh_host_key_dir/ssh_host_ed25519_key"
generate_host_key rsa "$ssh_host_key_dir/ssh_host_rsa_key" -b 3072

/usr/sbin/sshd -t -o "SetEnv=$ssh_session_environment"

/usr/sbin/sshd -D -e -o "SetEnv=$ssh_session_environment" &
service_pids+=("$!")

/docker-entrypoint.sh nginx -g 'daemon off;' &
service_pids+=("$!")

set +e
wait -n "${service_pids[@]}"
service_status=$?
set -e

exit "$service_status"
