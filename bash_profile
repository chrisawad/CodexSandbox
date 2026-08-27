# Preserve the base image's normal interactive Bash configuration.
if [[ -f /home/sandbox/.bashrc ]]; then
    source /home/sandbox/.bashrc
fi

# Interactive SSH login shells should begin in the workspace.
cd /home/sandbox/src
