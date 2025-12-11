#!/bin/sh
# shellcheck shell=dash

# shellcheck disable=SC2039  # local is non-POSIX
has_local() {
  # shellcheck disable=SC2034  # deliberately unused
  local _has_local
}
has_local 2>/dev/null || alias local=typeset

set -eu

if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
  set -x
fi

# --- configuration ---

GITHUB_REPO="tkk2112/dotfiles"
GIT_USER_EMAIL="thomas@sl.m04r.space"
PULL_REPO_URL="https://github.com/${GITHUB_REPO}.git"
PUSH_REPO_URL="git@github.com:${GITHUB_REPO}.git"
DEFAULT_DIR="${HOME}/.dotfiles"

# --- flags ---

ASSUME_YES_FLAG=100
NO_UPDATE_FLAG=101

# ----------------------

if ! command -v git >/dev/null 2>&1; then
  printf "git is required to bootstrap this repo. Install git and rerun.\n" >&2
  exit 1
fi

EXEC_DIR="$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)"

is_our_repo() {
  local _dir="$1"
  local _repo_github_var

  [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Checking if %s is our repo\n' "$_dir" >&2

  if [ ! -d "$_dir" ]; then
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s is not a directory\n' "$_dir" >&2
    return 1
  fi

  if [ ! -f "$_dir/setup.sh" ]; then
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s/setup.sh does not exist\n' "$_dir" >&2
    return 1
  fi

  _repo_github_var="$(grep '^GITHUB_REPO=' "$_dir/setup.sh" 2>/dev/null | cut -d'"' -f2 || true)"
  [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Found setup.sh with GITHUB_REPO=%s (expecting %s)\n' "$_repo_github_var" "$GITHUB_REPO" >&2

  if [ "$_repo_github_var" = "$GITHUB_REPO" ]; then
    return 0
  fi

  return 1
}

repo_dir=""
if printenv DOTFILES_LOCATION >/dev/null; then
  [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: DOTFILES_LOCATION is set to %s\n' "$DOTFILES_LOCATION" >&2

  if is_our_repo "$DOTFILES_LOCATION"; then
    repo_dir="$DOTFILES_LOCATION"
  else
    printf 'Error: DOTFILES_LOCATION is set to %s, but it does not contain our repository\n' "$DOTFILES_LOCATION" >&2
    exit 1
  fi
elif is_our_repo "$EXEC_DIR"; then
  repo_dir="$EXEC_DIR"
elif is_our_repo "$DEFAULT_DIR"; then
  repo_dir="$DEFAULT_DIR"
else
  # Only clone if we don't have the repo anywhere
  [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: No existing repo found, cloning to %s\n' "$DEFAULT_DIR" >&2
  git clone "$PULL_REPO_URL" "$DEFAULT_DIR"
  repo_dir="$DEFAULT_DIR"
fi

if [ -n "$repo_dir" ]; then
  cd "$repo_dir" || {
    printf 'Failed to change directory to %s\n' "$repo_dir" >&2
    exit 1
  }
else
  printf 'Failed to setup .dotfiles folder at %s\n' "$repo_dir" >&2
  exit 1
fi

if [ "$repo_dir" != "$EXEC_DIR" ] && [ -x "$repo_dir/setup.sh" ]; then
  exec "$repo_dir/setup.sh" "$@"
fi

scripts="${repo_dir}/scripts"
# shellcheck disable=SC1091  # cannot follow sourced file
. "${scripts}/options.sh"

PROCESSED_ARGS=""
process_arguments "$ASSUME_YES_FLAG" "$NO_UPDATE_FLAG" "$@"
status=$?
args="$PROCESSED_ARGS"

if [ $status -ne 0 ]; then
  info "$args"
  exit 0
fi

if ! has_flag "$NO_UPDATE_FLAG"; then
  update_dotfiles_repo "$ASSUME_YES_FLAG" "$PUSH_REPO_URL" "$GIT_USER_EMAIL" "$repo_dir" "$PULL_REPO_URL"
fi

# Source library after potential repo update
# shellcheck disable=SC1091  # cannot follow sourced file
. "${scripts}/library.sh"

if has_flag "$NO_UPDATE_FLAG"; then
  export DOTFILES_UV_NO_UPDATE=1
fi
# shellcheck disable=SC1091  # cannot follow sourced file
. "${scripts}/install_uv.sh"
export UV_PROJECT="${repo_dir}"
export UV_WORKING_DIRECTORY="${repo_dir}"
export UV_FROZEN=1

uv sync

if ! has_flag "$NO_UPDATE_FLAG"; then
  platform="$(detect_platform)"
  if has_pwless_sudo; then
    echo "Passwordless sudo available, installing system packages..."
    case "$platform" in
    debian)
      install_package "apt-utils"
      ;;
    fedora)
      install_package "python3-libdnf5"
      ;;
    esac
  else
    echo "No passwordless sudo available, skipping system package installation"
    echo "You may need to manually install platform-specific packages:"
    case "$platform" in
    debian)
      echo "  - apt-utils"
      ;;
    fedora)
      echo "  - python3-libdnf5"
      ;;
    esac
  fi
fi

create_ansible_config_dirs

export ANSIBLE_COLLECTIONS_PATH="${repo_dir}/.config/collections"
export ANSIBLE_CONFIG="${repo_dir}/ansible.cfg"
export ANSIBLE_LIBRARY="${repo_dir}/library"
export ANSIBLE_MODULE_UTILS="${repo_dir}/.config/plugins/module_utils"
export ANSIBLE_ROLES_PATH="${repo_dir}/roles"

if ! has_flag "$NO_UPDATE_FLAG"; then
  echo "Installing Ansible collections..."
  uv run ansible-galaxy collection install --requirements-file requirements.yml --upgrade
fi
# shellcheck disable=SC2086  # double quote to prevent globbing and word splitting
uv run ansible-playbook site.yml $PROCESSED_ARGS
