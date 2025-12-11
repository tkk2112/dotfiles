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
    [ -n "$1" ] || return 0
    eval "__DOTFILES_FLAG_$1=1"
}

unset_flag() {
    [ -n "$1" ] || return 0
    eval "unset __DOTFILES_FLAG_$1"
}

has_flag() {
    [ -n "$1" ] || return 1
    eval "[ \"\${__DOTFILES_FLAG_$1:-}\" = 1 ]"
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

ensure_pkg_repo_is_uptodate() {
    local _pkgsys_updated_flag=200
    local _platform
    _platform="$(detect_platform)"
    if ! has_flag "$_pkgsys_updated_flag"; then
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
        set_flag $_pkgsys_updated_flag
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
    local _pull_url="${5}"
    local _target_branch="main"

    if [ -n "${DOTFILES_CI:-}" ]; then
        if [ -n "${GITHUB_HEAD_REF:-}" ]; then
            _target_branch="$GITHUB_HEAD_REF"
            [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Using PR branch: %s\n' "$_target_branch" >&2
        elif [ -n "${GITHUB_REF_NAME:-}" ]; then
            _target_branch="$GITHUB_REF_NAME"
            [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Using ref: %s\n' "$_target_branch" >&2
        fi
    fi

    if [ ! -d "$_repo_dir/.git" ]; then
        [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: No .git directory found, initializing from %s\n' "$_pull_url" >&2
        info "Converting file copy to git repository..."

        (
            cd "$_repo_dir" || err "Failed to change directory to $_repo_dir"

            git init >/dev/null 2>&1 || err "Failed to initialize git repository in $_repo_dir"
            git remote add origin "$_pull_url" >/dev/null 2>&1 || err "Failed to add remote origin"

            if ! git fetch origin >/dev/null 2>&1; then
                err "Could not fetch from origin; keeping as file copy."
            fi

            git branch -M "$_target_branch" >/dev/null 2>&1 || warn "Could not rename branch to $_target_branch"
            git branch --set-upstream-to="origin/$_target_branch" "$_target_branch" >/dev/null 2>&1 || warn "Could not set upstream tracking"
            git reset "origin/$_target_branch" >/dev/null 2>&1 || warn "Could not reset to origin/$_target_branch"

            info "Converted to git repository successfully."
        )
    fi

    [ -d "$_repo_dir/.git" ] || return 0

    (
        cd "$_repo_dir" || err "Failed to change directory to $_repo_dir"
        git rev-parse --is-inside-work-tree >/dev/null 2>&1 || err "$_repo_dir is not a valid git repository"
        git remote get-url origin >/dev/null 2>&1 || err "Git repository has no remote 'origin' configured"

        git remote -v | grep -qE '^origin\s+https:.*\(push\)$' &&
            git remote set-url --push origin "${_origin_push_url}"

        [ "$(git config user.email)" = "${_user_email}" ] || git config user.email "${_user_email}"

        if ! git fetch --prune origin >/dev/null 2>&1; then
            err "Could not reach origin; skipping update."
        fi

        info "Updating to latest from origin/$_target_branch..."
        if git rebase --autostash --rebase-merges "origin/$_target_branch"; then
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
