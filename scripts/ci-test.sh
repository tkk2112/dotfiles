#!/bin/sh
set -eu

repo_root="${DOTFILES_LOCATION:-$(git rev-parse --show-toplevel)}"

# Keep the environment established for our installed user tools available to
# both the install validation and the Neovim test suite.
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

"$repo_root/scripts/ci-install.sh"

printf '\n==> Running Neovim test suite\n'
"$repo_root/scripts/test-nvim.sh"
