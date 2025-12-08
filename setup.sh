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
DOTFILES_DIR="$(printenv DOTFILES_LOCATION || true)"
DEFAULT_DIR="${HOME}/.dotfiles"
ANSIBLE_COLLECTIONS="community.general ansible.posix"

# --- flags ---
ASSUME_YES_FLAG=100
NO_UPDATE_FLAG=101

if ! command -v git >/dev/null 2>&1; then
  printf "git is required to bootstrap this repo. Install git and rerun.\n" >&2
  exit 1
fi

EXEC_DIR="$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)"

is_git_repo() {
  local _dir="$1"

  [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Checking if %s is a git repo\n' "$_dir" >&2

  if [ ! -d "$_dir" ]; then
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s is not a directory\n' "$_dir" >&2
    return 1
  fi

  if [ ! -e "$_dir/.git" ]; then
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s/.git does not exist\n' "$_dir" >&2
    return 1
  fi

  if git -C "$_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s is a valid git repository\n' "$_dir" >&2
    return 0
  else
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s has .git but git rev-parse failed\n' "$_dir" >&2
    return 1
  fi
}

is_our_repo() {
  local _dir="$1"
  local _origin_url
  local _repo_github_var

  if ! is_git_repo "$_dir"; then
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s is not a git repo\n' "$_dir" >&2
    return 1
  fi

  if [ -f "$_dir/setup.sh" ]; then
    _repo_github_var="$(grep '^GITHUB_REPO=' "$_dir/setup.sh" 2>/dev/null | cut -d'"' -f2 || true)"
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Found setup.sh with GITHUB_REPO=%s (expecting %s)\n' "$_repo_github_var" "$GITHUB_REPO" >&2
    if [ "$_repo_github_var" = "$GITHUB_REPO" ]; then
      return 0
    fi
  else
    [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: %s/setup.sh does not exist\n' "$_dir" >&2
  fi

  _origin_url="$(git -C "$_dir" remote get-url origin 2>/dev/null || true)"
  [ "${DOTFILES_DEBUG:-}" = "1" ] && printf 'DEBUG: Git remote origin URL: %s\n' "$_origin_url" >&2

  if [ -z "$_origin_url" ]; then
    return 1
  fi

  if printf '%s\n' "$_origin_url" | grep -q "${GITHUB_REPO}"; then
    return 0
  fi
  return 1
}

repo_dir=""
if printenv DOTFILES_LOCATION >/dev/null; then
  if is_git_repo "$DOTFILES_LOCATION"; then
    repo_dir="$DOTFILES_LOCATION"
    if ! is_our_repo "$DOTFILES_LOCATION"; then
      printf 'Error: DOTFILES_LOCATION is set to %s, which is already a git repository for %s\n' "$DOTFILES_DIR" "${GITHUB_REPO}" >&2
      exit 1
    fi
  else
    git clone "$PULL_REPO_URL" "$DOTFILES_LOCATION"
  fi
elif is_git_repo "$EXEC_DIR"; then
  if is_our_repo "$EXEC_DIR"; then
    repo_dir="$EXEC_DIR"
  fi
elif is_git_repo "$DEFAULT_DIR"; then
  if is_our_repo "$DEFAULT_DIR"; then
    repo_dir="$DEFAULT_DIR"
  fi
else
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
  update_dotfiles_repo "$ASSUME_YES_FLAG" "$PUSH_REPO_URL" "$GIT_USER_EMAIL" "$repo_dir"
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
  case "$platform" in
  debian)
    install_package "apt-utils"
    ;;
  fedora)
    install_package "python3-libdnf5"
    ;;
  esac

  uv run pre-commit install

  if [ "$platform" = "debian" ]; then
    uv pip install six python-debian
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
  for collection in $ANSIBLE_COLLECTIONS; do
    echo "  - $collection"
    uv run ansible-galaxy collection install "$collection" --upgrade
  done
fi
# shellcheck disable=SC2086  # double quote to prevent globbing and word splitting
uv run ansible-playbook site.yml $PROCESSED_ARGS
