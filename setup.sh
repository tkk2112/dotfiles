#!/bin/sh

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

install_bootstrap_prerequisites() {
  packages=""

  command -v age-keygen >/dev/null 2>&1 || packages="$packages age"
  command -v jq >/dev/null 2>&1 || packages="$packages jq"
  command -v pass-cli >/dev/null 2>&1 || packages="$packages proton-pass-cli"

  [ -n "$packages" ] || return 0
  command -v brew >/dev/null 2>&1 || return 0

  printf 'Installing optional bootstrap tools with Homebrew:%s\n' "$packages"

  if [ "$(uname -s)" = "Linux" ] && ! command -v bwrap >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    run env HOMEBREW_NO_SANDBOX_LINUX=1 brew install $packages || return 0
  else
    # shellcheck disable=SC2086
    run brew install $packages || return 0
  fi
}

print_limited_install_notice() {
  missing=""

  for command_name in age-keygen jq pass-cli; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing="${missing} ${command_name}"
    fi
  done

  if [ -n "$missing" ]; then
    printf 'Continuing with a limited install; unavailable optional tools:%s\n' \
      "$missing" >&2
  fi
}

should_exclude_encrypted() {
  if [ "${DOTFILES_CI:-}" = "true" ]; then
    return 0
  fi

  key_file="$HOME/.config/chezmoi/key.txt"

  if command -v age >/dev/null 2>&1 && [ -s "$key_file" ]; then
    return 1
  fi

  # The run_once_before age provisioner can create the identity during apply.
  if command -v age-keygen >/dev/null 2>&1 && \
    command -v pass-cli >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

apply_dotfiles() {
  source_dir=$1
  shift

  if should_exclude_encrypted; then
    printf '%s\n' \
      'Age identity unavailable; applying everything except encrypted files.' >&2

    if [ -n "$source_dir" ]; then
      run chezmoi --source "$source_dir" apply --exclude encrypted "$@"
    else
      run chezmoi apply --exclude encrypted "$@"
    fi
  elif [ -n "$source_dir" ]; then
    run chezmoi --source "$source_dir" apply "$@"
  else
    run chezmoi apply "$@"
  fi
}

add_homebrew_to_path

if [ "${DOTFILES_CI:-}" != "true" ]; then
  install_bootstrap_prerequisites
  print_limited_install_notice
fi

# Chezmoi renders executable scripts in its temporary directory. Some managed
# systems mount /tmp with noexec, so keep temporary files on the home dataset.
if [ -z "${TMPDIR:-}" ]; then
  TMPDIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmp"
  mkdir -p "$TMPDIR"
  chmod 700 "$TMPDIR"
  export TMPDIR
fi

if [ -n "$repo_dir" ] && [ -f "$repo_dir/.chezmoiroot" ]; then
  log "Using local chezmoi source: $repo_dir"

  if [ "${DOTFILES_CI:-}" = "true" ]; then
    run chezmoi init --source "$repo_dir" --promptDefaults
  else
    run chezmoi init --source "$repo_dir"
  fi

  apply_dotfiles "$repo_dir" "$@"
else
  log "Using remote chezmoi source: $PULL_REPO_URL"

  if [ "${DOTFILES_CI:-}" = "true" ]; then
    run chezmoi init "$PULL_REPO_URL" --promptDefaults
  else
    run chezmoi init "$PULL_REPO_URL"
  fi

  apply_dotfiles "" "$@"
fi
