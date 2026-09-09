#!/bin/bash
set -Eeuo pipefail

readonly ssh_host_key_dir=/home/sandbox/.ssh/host-keys
readonly sandbox_home=/home/sandbox
readonly source_dir=/home/sandbox/src
readonly setup_dir=/etc/setup
readonly default_agents_file="$setup_dir/AGENTS.md"
readonly default_bash_profile="$setup_dir/bash_profile"
readonly default_bashrc="$setup_dir/bashrc"
readonly default_codex_config="$setup_dir/codex-config.toml"
readonly bash_profile="$sandbox_home/.bash_profile"
readonly bashrc="$sandbox_home/.bashrc"
readonly codex_config="$sandbox_home/.codex/config.toml"
readonly sandbox_uid="$(id -u)"
readonly sandbox_gid="$(id -g)"

: "${GIT_CONFIG_USER_NAME:=Codex Sandbox}"
: "${GIT_CONFIG_USER_EMAIL:=}"
: "${SSH_AUTH_SOCK:=/ssh-auth.sock}"
: "${DOCKER_HOST:=tcp://docker:2376}"
: "${DOCKER_TLS_VERIFY:=1}"
: "${DOCKER_CERT_PATH:=/certs/client}"
: "${INTERNAL_SERVICE_PORT:=3000}"
: "${EXTERNAL_SERVICE_PORT:=3000}"

if [[ ! "$INTERNAL_SERVICE_PORT" =~ ^[0-9]+$ ]] || ((INTERNAL_SERVICE_PORT < 1 || INTERNAL_SERVICE_PORT > 65535)); then
    printf 'Invalid INTERNAL_SERVICE_PORT: %q. Expected an integer from 1 through 65535.\n' \
        "$INTERNAL_SERVICE_PORT" >&2
    exit 1
fi

if [[ ! "$EXTERNAL_SERVICE_PORT" =~ ^[0-9]+$ ]] || ((EXTERNAL_SERVICE_PORT < 1 || EXTERNAL_SERVICE_PORT > 65535)); then
    printf 'Invalid EXTERNAL_SERVICE_PORT: %q. Expected an integer from 1 through 65535.\n' \
        "$EXTERNAL_SERVICE_PORT" >&2
    exit 1
fi

export SSH_AUTH_SOCK DOCKER_HOST DOCKER_TLS_VERIFY DOCKER_CERT_PATH
export INTERNAL_SERVICE_PORT EXTERNAL_SERVICE_PORT

if [[ ! -S "$SSH_AUTH_SOCK" ]]; then
    printf 'Warning: no SSH agent socket is available at %q; SSH login and SSH-based Git authentication are disabled.\n' \
        "$SSH_AUTH_SOCK" >&2
fi

# Compose's short bind syntax creates missing sources as root before this
# process starts. Normalize only the two user-owned mount points; never chown
# the persistent home recursively because it may contain intentional ownership.
sudo -n mkdir -p "$source_dir"
sudo -n chown "$sandbox_uid:$sandbox_gid" "$sandbox_home" "$source_dir"

mkdir -p "$sandbox_home/.codex" "$sandbox_home/.config" "$ssh_host_key_dir"
mkdir -p "$sandbox_home/.cache" "$source_dir"

# Docker Desktop bind mounts can preserve safe file modes while rejecting
# chmod on the mount-point directories themselves. Apply the preferred modes
# where supported; sshd still validates the actual private host-key files.
chmod 0700 "$sandbox_home" "$sandbox_home/.ssh" "$sandbox_home/.codex" \
    "$sandbox_home/.config" "$ssh_host_key_dir" 2>/dev/null || true
chmod 0755 "$sandbox_home/.cache" "$source_dir" 2>/dev/null || true

# Seed normal home-directory files only when the persistent home does not
# already provide them. User changes survive all later container starts.
if [[ ! -e "$bash_profile" && ! -L "$bash_profile" ]]; then
    install -m 0644 "$default_bash_profile" "$bash_profile"
fi

if [[ ! -e "$bashrc" && ! -L "$bashrc" ]]; then
    install -m 0644 "$default_bashrc" "$bashrc"
fi

# Codex discovers global guidance in ~/.codex. Keep that default discovery path
# linked to the image-managed instructions unless the user supplies a file.
if [[ ! -e "$sandbox_home/.codex/AGENTS.md" && ! -L "$sandbox_home/.codex/AGENTS.md" ]]; then
    ln -s "$default_agents_file" "$sandbox_home/.codex/AGENTS.md"
fi

# Seed the normal Codex configuration path once.
if [[ ! -e "$codex_config" && ! -L "$codex_config" ]]; then
    install -m 0600 "$default_codex_config" "$codex_config"
fi

git config --global user.name "$GIT_CONFIG_USER_NAME"

if [[ -n "$GIT_CONFIG_USER_EMAIL" ]]; then
    git config --global user.email "$GIT_CONFIG_USER_EMAIL"
fi

readonly ssh_session_environment="SSH_AUTH_SOCK=$SSH_AUTH_SOCK DOCKER_HOST=$DOCKER_HOST DOCKER_TLS_VERIFY=$DOCKER_TLS_VERIFY DOCKER_CERT_PATH=$DOCKER_CERT_PATH INTERNAL_SERVICE_PORT=$INTERNAL_SERVICE_PORT EXTERNAL_SERVICE_PORT=$EXTERNAL_SERVICE_PORT"

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

    chmod 0600 "$key_path" 2>/dev/null || true
    chmod 0644 "${key_path}.pub" 2>/dev/null || true
}

generate_host_key ed25519 "$ssh_host_key_dir/ssh_host_ed25519_key"
generate_host_key rsa "$ssh_host_key_dir/ssh_host_rsa_key" -b 3072

/usr/sbin/sshd -t -o "SetEnv=$ssh_session_environment"

exec /usr/sbin/sshd -D -e -o "SetEnv=$ssh_session_environment"
