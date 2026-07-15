#!/bin/sh
set -eu

GITHUB_REPO="tkk2112/dotfiles"
PULL_REPO_URL="https://github.com/${GITHUB_REPO}.git"
DEFAULT_SOURCE="${HOME}/.local/share/chezmoi"

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
  set -x
fi

log() {
  printf '%s\n' "$*"
}

run() {
  printf '+ %s\n' "$*"
  "$@"
}

if ! command -v git >/dev/null 2>&1; then
  printf 'git is required to bootstrap this repo. Install git and rerun.\n' >&2
  exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
  bin_dir="${HOME}/.local/bin"
  mkdir -p "$bin_dir"

  if command -v curl >/dev/null 2>&1; then
    log "Installing chezmoi with curl into $bin_dir"
    sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "$bin_dir"
  elif command -v wget >/dev/null 2>&1; then
    log "Installing chezmoi with wget into $bin_dir"
    sh -c "$(wget -qO- https://get.chezmoi.io)" -- -b "$bin_dir"
  else
    printf 'chezmoi is not installed and neither curl nor wget is available.\n' >&2
    exit 1
  fi

  PATH="${bin_dir}:${PATH}"
  export PATH
fi

repo_dir="${DOTFILES_LOCATION:-}"

if [ -z "$repo_dir" ]; then
  exec_dir="$(CDPATH='' cd "$(dirname "$0")" && pwd)"

  if [ -f "$exec_dir/.chezmoiroot" ]; then
    repo_dir="$exec_dir"
  elif [ -f "$DEFAULT_SOURCE/.chezmoiroot" ]; then
    repo_dir="$DEFAULT_SOURCE"
  fi
fi

log "DOTFILES_CI=${DOTFILES_CI:-}"
log "DOTFILES_LOCATION=${DOTFILES_LOCATION:-}"
log "repo_dir=${repo_dir:-}"

add_homebrew_to_path() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  for prefix in \
    /home/linuxbrew/.linuxbrew \
    "$HOME/.linuxbrew"; do
    if [ -x "$prefix/bin/brew" ]; then
      PATH="$prefix/bin:$prefix/sbin:$PATH"
      export PATH
      return 0
    fi
  done
}

require_commands() {
  missing=""

  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing="${missing}
  - ${command_name}"
    fi
  done

  if [ -z "$missing" ]; then
    return 0
  fi

  printf 'Missing bootstrap prerequisites:%s\n' "$missing" >&2
  printf '%s\n' \
    'Install these commands before running setup.sh.' \
    'Fedora example:' \
    '  sudo dnf install age jq' \
    '  brew install proton-pass-cli' >&2
  exit 127
}

add_homebrew_to_path

if [ "${DOTFILES_CI:-}" != "true" ]; then
  require_commands age-keygen jq pass-cli
fi

if [ -n "$repo_dir" ] && [ -f "$repo_dir/.chezmoiroot" ]; then
  log "Using local chezmoi source: $repo_dir"

  if [ "${DOTFILES_CI:-}" = "true" ]; then
    run chezmoi init --source "$repo_dir" --promptDefaults
    run chezmoi --source "$repo_dir" apply --exclude encrypted "$@"
  else
    run chezmoi init --source "$repo_dir"
    run chezmoi --source "$repo_dir" apply "$@"
  fi
else
  log "Using remote chezmoi source: $PULL_REPO_URL"

  if [ "${DOTFILES_CI:-}" = "true" ]; then
    run chezmoi init "$PULL_REPO_URL" --promptDefaults
    run chezmoi apply --exclude encrypted "$@"
  else
    run chezmoi init "$PULL_REPO_URL"
    run chezmoi apply "$@"
  fi
fi
