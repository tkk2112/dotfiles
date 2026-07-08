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
    printf "git is required to bootstrap this repo. Install git and rerun.\n" >&2
    exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
    bin_dir="${HOME}/.local/bin"
    mkdir -p "$bin_dir"

    if command -v curl >/dev/null 2>&1; then
        log "Installing chezmoi with curl into $bin_dir"
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$bin_dir"
    elif command -v wget >/dev/null 2>&1; then
        log "Installing chezmoi with wget into $bin_dir"
        sh -c "$(wget -qO- get.chezmoi.io)" -- -b "$bin_dir"
    else
        printf "chezmoi is not installed and neither curl nor wget is available.\n" >&2
        exit 1
    fi

    PATH="${bin_dir}:${PATH}"
    export PATH
fi

repo_dir="${DOTFILES_LOCATION:-}"

if [ -z "$repo_dir" ]; then
    exec_dir="$(CDPATH="" cd "$(dirname "$0")" && pwd)"

    if [ -f "$exec_dir/.chezmoiroot" ]; then
        repo_dir="$exec_dir"
    elif [ -f "$DEFAULT_SOURCE/.chezmoiroot" ]; then
        repo_dir="$DEFAULT_SOURCE"
    fi
fi

chezmoi_init_flags=""

if [ "${DOTFILES_CI:-}" = "true" ]; then
    chezmoi_init_flags="--promptDefaults"
fi

log "DOTFILES_CI=${DOTFILES_CI:-}"
log "DOTFILES_LOCATION=${DOTFILES_LOCATION:-}"
log "repo_dir=${repo_dir:-}"
log "chezmoi_init_flags=${chezmoi_init_flags:-}"

if [ -n "$repo_dir" ] && [ -f "$repo_dir/.chezmoiroot" ]; then
    log "Using local chezmoi source: $repo_dir"
    run chezmoi init --source "$repo_dir" $chezmoi_init_flags
    run chezmoi --source "$repo_dir" apply "$@"
else
    log "Using remote chezmoi source: $PULL_REPO_URL"
    run chezmoi init "$PULL_REPO_URL" $chezmoi_init_flags
    run chezmoi apply "$@"
fi
