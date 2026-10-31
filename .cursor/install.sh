#!/usr/bin/env bash
set -euo pipefail

if [ ! -x "${HOME}/.local/bin/mise" ]; then
  curl -fsSL https://mise.run/bash | sh
fi

export PATH="${HOME}/.local/bin:${PATH}"
eval "$(mise activate bash)"

# swift.org's Linux toolchain needs the ncurses 6 sonames. The default image does not ship them.
if ! ldconfig -p 2>/dev/null | grep -q 'libncurses\.so\.6'; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libncurses6
fi

cd /workspace
mise trust --yes
mise install
mise reshim

swiftc --version

# Cloud Agent Skills menu and runtime read ~/.cursor/skills-cursor. Existing skill folders are left in place.
curl -fsSL https://raw.githubusercontent.com/nikolaybotev/local-skills/main/install.sh | sh -s -- ~/.cursor/skills-cursor
