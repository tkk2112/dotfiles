#!/bin/sh
# Install or update uv in ~/.local/bin.

set -e

UV_BIN="${UV_BIN:-${HOME}/.local/bin/uv}"

install_uv() {
  echo "Installing uv to ${UV_BIN}..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
  export PATH="${HOME}/.local/bin:${PATH}"
}

update_uv() {
  if [ -n "${DOTFILES_UPDATE_UV_QUIET:-}" ]; then
    "${1}" self update >/dev/null 2>&1
  else
    echo "Updating uv at ${1}..."
    "${1}" self update
  fi
}

uv_path="$(command -v uv 2>/dev/null || true)"

if [ -n "$uv_path" ]; then
  update_uv "$uv_path"
elif [ -x "$UV_BIN" ]; then
  update_uv "$UV_BIN"
  path="$(dirname "$UV_BIN"):${PATH}"
  export PATH="$path"
else
  install_uv
fi
