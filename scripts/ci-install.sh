#!/bin/sh
set -eu

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
  set -x
fi

ci_pkgs="${DOTFILES_CI_PKGS:-git curl jq}"

log() {
  printf '%s\n' "$*"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

section() {
  printf '\n==> %s\n' "$*"
}

log "Starting CI dotfiles install"
log "HOME=$HOME"
log "PWD=$PWD"
log "DOTFILES_LOCATION=${DOTFILES_LOCATION:-}"
log "DOTFILES_CI=${DOTFILES_CI:-}"
log "PATH=$PATH"

if [ -f /etc/os-release ]; then
  log ""
  log "/etc/os-release:"
  cat /etc/os-release
fi

if [ "${DOTFILES_CI_SKIP_PACKAGE_SETUP:-}" = "1" ]; then
  log "Skipping CI package setup because DOTFILES_CI_SKIP_PACKAGE_SETUP=1"
else
  section "Installing CI dependencies"

  if command -v brew >/dev/null 2>&1; then
    log "macOS CI packages: $ci_pkgs"
    run brew install $ci_pkgs || true
  else
    ci_pkgs="$ci_pkgs ca-certificates"
    log "Linux CI packages: $ci_pkgs"

    if command -v apt-get >/dev/null 2>&1; then
      run apt-get update
      run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $ci_pkgs
    elif command -v dnf >/dev/null 2>&1; then
      run dnf install -y $ci_pkgs
    elif command -v apk >/dev/null 2>&1; then
      run apk add --no-cache $ci_pkgs
    elif command -v pacman >/dev/null 2>&1; then
      run pacman -Sy --noconfirm --needed $ci_pkgs
    else
      printf 'Unsupported package manager\n' >&2
      exit 1
    fi
  fi
fi

export DOTFILES_CI=true
export DOTFILES_LOCATION="${DOTFILES_LOCATION:-${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)}}"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

if command -v apt-get >/dev/null 2>&1; then
  section "Installing tree-sitter CLI"
  run "$DOTFILES_LOCATION/scripts/install-tree-sitter-cli.sh"

  section "Ensuring a supported Neovim version"
  run "$DOTFILES_LOCATION/scripts/install-neovim.sh"
fi

section "Running setup.sh"
run sh "$DOTFILES_LOCATION/setup.sh"

section "Running install validation"
run "$DOTFILES_LOCATION/scripts/test-install.sh"

section "Running profile validation"
run "$DOTFILES_LOCATION/scripts/test-profiles.sh"
