#!/bin/sh
set -eu

GITHUB_REPO="tkk2112/dotfiles"
PULL_REPO_URL="https://github.com/${GITHUB_REPO}.git"
DEFAULT_SOURCE="${HOME}/.local/share/chezmoi"

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
    set -x
fi

if ! command -v git >/dev/null 2>&1; then
    printf "git is required to bootstrap this repo. Install git and rerun.\n" >&2
    exit 1
fi

if ! command -v chezmoi >/dev/null 2>&1; then
    bin_dir="${HOME}/.local/bin"
    mkdir -p "$bin_dir"

    if command -v curl >/dev/null 2>&1; then
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$bin_dir"
    elif command -v wget >/dev/null 2>&1; then
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

if [ -n "$repo_dir" ] && [ -f "$repo_dir/.chezmoiroot" ]; then
    chezmoi init --source "$repo_dir"
    chezmoi --source "$repo_dir" apply "$@"
else
    chezmoi init "$PULL_REPO_URL"
    chezmoi apply "$@"
fi
