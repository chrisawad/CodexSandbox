# Preserve the base image's normal interactive Bash configuration.
if [[ -f /home/codex/.bashrc ]]; then
    source /home/codex/.bashrc
fi

# Interactive SSH login shells should begin in the workspace.
cd /home/codex/src
