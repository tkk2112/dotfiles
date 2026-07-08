#!/bin/sh
set -eu

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
    set -x
fi

pkgs="${DOTFILES_CI_PKGS:-git curl ca-certificates zsh tmux}"

log() {
    printf '%s\n' "$*"
}

run() {
    printf '+ %s\n' "$*"
    "$@"
}

log "Starting CI dotfiles install"
log "HOME=$HOME"
log "PWD=$PWD"
log "DOTFILES_LOCATION=${DOTFILES_LOCATION:-}"
log "DOTFILES_CI=${DOTFILES_CI:-}"
log "PATH=$PATH"
log "Packages: $pkgs"

if [ -f /etc/os-release ]; then
    log ""
    log "/etc/os-release:"
    cat /etc/os-release
fi

if command -v apt-get >/dev/null 2>&1; then
    run apt-get update
    DEBIAN_FRONTEND=noninteractive run apt-get install -y --no-install-recommends $pkgs
elif command -v dnf >/dev/null 2>&1; then
    run dnf install -y $pkgs
elif command -v apk >/dev/null 2>&1; then
    run apk add --no-cache $pkgs
elif command -v pacman >/dev/null 2>&1; then
    run pacman -Sy --noconfirm --needed $pkgs
elif command -v brew >/dev/null 2>&1; then
    run brew install zsh tmux || true
else
    printf 'Unsupported package manager\n' >&2
    exit 1
fi

export DOTFILES_CI=true
export DOTFILES_LOCATION="${DOTFILES_LOCATION:-$GITHUB_WORKSPACE}"
export PATH="$HOME/.local/bin:$PATH"

log ""
log "Running setup.sh"
run sh "$DOTFILES_LOCATION/setup.sh"

log ""
log "Running install validation"
run "$DOTFILES_LOCATION/scripts/test-install.sh"
