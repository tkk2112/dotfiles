#!/bin/sh
set -eu

cargo_home="${CARGO_HOME:-$HOME/.cargo}"
cargo_bin="$cargo_home/bin"
cargo_binstall="$cargo_bin/cargo-binstall"

export CARGO_HOME="$cargo_home"
export PATH="$cargo_bin:$PATH"

if command -v tree-sitter >/dev/null 2>&1; then
  printf 'tree-sitter is already installed: %s\n' "$(command -v tree-sitter)"
  tree-sitter --version
  exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required to install cargo-binstall\n' >&2
  exit 1
fi

if ! command -v cargo-binstall >/dev/null 2>&1; then
  printf 'Installing cargo-binstall\n'

  curl -L \
    --proto '=https' \
    --tlsv1.2 \
    -sSf \
    https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh \
    | sh
fi

if command -v cargo-binstall >/dev/null 2>&1; then
  cargo_binstall="$(command -v cargo-binstall)"
elif [ ! -x "$cargo_binstall" ]; then
  printf 'cargo-binstall was installed but could not be found\n' >&2
  exit 1
fi

printf 'Installing tree-sitter CLI\n'
"$cargo_binstall" --no-confirm tree-sitter-cli

if ! command -v tree-sitter >/dev/null 2>&1; then
  printf 'tree-sitter was installed but is not available on PATH\n' >&2
  printf 'Add this directory to PATH: %s\n' "$cargo_bin" >&2
  exit 1
fi

tree-sitter --version
