#!/bin/sh
# shellcheck shell=dash

# shellcheck disable=SC2039  # local is non-POSIX
has_local() {
    # shellcheck disable=SC2034  # deliberately unused
    local _has_local
}
has_local 2>/dev/null || alias local=typeset

err() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

warn() {
    printf 'Warning: %s\n' "$1" >&2
}

info() {
    printf '%s\n' "$1"
}

ret() {
    printf '%s\n' "$1"
}

set_flag() {
    [ -n "$1" ] && eval "exec $1>&1"
}

unset_flag() {
    [ -n "$1" ] && eval "exec $1>&-"
}

has_flag() {
    [ -n "$1" ] && [ -e "/dev/fd/$1" ]
}

has_pwless_sudo() {
    sudo -n true 2>/dev/null
    return $?
}

detect_platform() {
    local _platform="unknown"
    case "$(uname -s)" in
    Darwin)
        _platform="macos"
        ;;
    Linux)
        if command -v apt-get >/dev/null 2>&1; then
            _platform="debian"
        elif command -v dnf >/dev/null 2>&1; then
            _platform="fedora"
        else
            _platform="linux"
        fi
        ;;
    esac
    ret "$_platform"
}

PKGSYS_UPDATED_FLAG=100
ensure_pkg_repo_is_uptodate() {
    local _platform
    _platform="$(detect_platform)"
    if ! has_flag "$PKGSYS_UPDATED_FLAG"; then
        case "$_platform" in
        debian)
            sudo DEBIAN_FRONTEND=noninteractive apt-get -qq update </dev/null >/dev/null
            ;;
        fedora)
            sudo dnf check-update -q >/dev/null 2>&1 || true
            ;;
        macos)
            : # Homebrew typically auto-updates during install
            ;;
        linux)
            warn "Package repository update not implemented for generic Linux"
            ;;
        *)
            err "Unknown platform: $_platform"
            ;;
        esac
        set_flag $PKGSYS_UPDATED_FLAG
    fi
}

need_cmd() {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
    return $?
}

install_package() {
    local _package="$1"
    local _platform
    _platform="$(detect_platform)"

    ensure_pkg_repo_is_uptodate

    case "$_platform" in
    debian)
        if ! dpkg -s "$_package" >/dev/null 2>&1; then
            info "Installing $_package on Debian/Ubuntu..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install -y "$_package" </dev/null >/dev/null
        fi
        ;;
    fedora)
        if ! rpm -q "$_package" >/dev/null 2>&1; then
            info "Installing $_package on Fedora..."
            sudo dnf install -y -q "$_package" >/dev/null 2>&1
        fi
        ;;
    macos)
        if ! brew list "$_package" >/dev/null 2>&1; then
            info "Installing $_package on macOS..."
            brew install "$_package"
        fi
        ;;
    linux)
        warn "Generic Linux package installation for $_package not implemented. Please install manually."
        ;;
    *)
        err "Unsupported platform: $_platform"
        ;;
    esac
}

install_bin_package() {
    local _package="$1"
    local _binary="${2:-$1}"

    if ! check_cmd "$_binary"; then
        info "$_binary not found."
        install_package "$_package"
    fi
}

update_dotfiles_repo() {
    local _skip_dirty_flag="${1}"
    local _origin_push_url="${2}"
    local _user_email="${3}"
    local _repo_dir="${4}"

    [ -d "$_repo_dir/.git" ] || return 0
    (
        cd "$_repo_dir" || return 0
        git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
        git remote get-url origin >/dev/null 2>&1 || return 0

        git remote -v | grep -qE '^origin\s+https:.*\(push\)$' &&
            git remote set-url --push origin "${_origin_push_url}"

        [ "$(git config user.email)" = "${_user_email}" ] || git config user.email "${_user_email}"

        if ! git fetch --prune origin >/dev/null 2>&1; then
            warn "Could not reach origin; skipping update."
        fi

        info "Updating to latest..."
        if git rebase --autostash --rebase-merges origin/main; then
            return 0
        fi

        warn "Update hit conflicts; unable to update automatically."
        git rebase --abort >/dev/null 2>&1 || true
        git status --porcelain
        if ! has_flag "${_skip_dirty_flag}"; then
            info "Press Enter to continue or Ctrl+C to abort..."
            read -r _
        else
            warn "Skipping prompt due to --skip-dirty-prompt flag."
        fi
    )
}

create_ansible_config_dirs() {
    mkdir -p .config/cache >/dev/null 2>&1 || true
    mkdir -p .config/fact_cache >/dev/null 2>&1 || true
    mkdir -p .config/retry_files >/dev/null 2>&1 || true
    mkdir -p .config/plugins >/dev/null 2>&1 || true
    for plugin in action become cache callback connection doc_fragments filter httpapi inventory lookup module_utils netconf strategy terminal test; do
        mkdir -p ".config/plugins/$plugin" || true
    done
}

case "$0" in
*/library.sh | library.sh)
    err "this file is a library and must be sourced"
    ;;
esac
