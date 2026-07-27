# Preserve the base image's normal interactive Bash configuration.
if [[ -f /root/.bashrc ]]; then
    source /root/.bashrc
fi

# Interactive SSH login shells should begin in the workspace.
cd /workspaces
