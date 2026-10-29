#!/usr/bin/env bash
set -euo pipefail

if [ ! -x "${HOME}/.local/bin/mise" ]; then
  curl -fsSL https://mise.run/bash | sh
fi

export PATH="${HOME}/.local/bin:${PATH}"
eval "$(mise activate bash)"

cd /workspace
mise trust --yes
mise install
mise reshim

swiftc --version

# Cloud Agent Skills menu and runtime read ~/.cursor/skills-cursor. Existing skill folders are left in place.
curl -fsSL https://raw.githubusercontent.com/OWNER/local-skills/main/install.sh | sh -s -- ~/.cursor/skills-cursor
