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
PULL_REPO_URL="https://github.com/tkk2112/dotfiles.git"
PUSH_REPO_URL="git@github.com:tkk2112/dotfiles.git"
GIT_USER_EMAIL="thomas@sl.m04r.space"
DOTFILES_DIR="${DOTFILES_LOCATION:-${HOME}/.dotfiles}"
ANSIBLE_COLLECTIONS="community.general ansible.posix"

# --- flags ---
ASSUME_YES_FLAG=100
NO_UPDATE_FLAG=101

if ! command -v git >/dev/null 2>&1; then
  printf "git is required to bootstrap this repo. Install git and rerun.\n" >&2
  exit 1
fi

EXEC_DIR="$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)"

ensure_repo() {
  local _execution_dir="$1"

  if git -C "$_execution_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local _origin_url
    _origin_url="$(git -C "$_execution_dir" remote get-url origin 2>/dev/null || true)"
    if printf '%s\n' "$_origin_url" | grep -qE "^(${PULL_REPO_URL}|${PUSH_REPO_URL})$"; then
      printf '%s\n' "$_execution_dir"
      return
    fi
  fi

  git clone "$PULL_REPO_URL" "$DOTFILES_DIR"
  printf '%s\n' "$DOTFILES_DIR"
}

repo_dir="$(ensure_repo "$EXEC_DIR")"
cd "$repo_dir" || {
  printf 'Failed to change directory to %s\n' "$repo_dir" >&2
  exit 1
}

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

# shellcheck disable=SC1091  # cannot follow sourced file
. "${scripts}/install_uv.sh"
export UV_PROJECT="${repo_dir}"
export UV_WORKING_DIRECTORY="${repo_dir}"
export UV_FROZEN=1

platform="$(detect_platform)"
case "$platform" in
debian)
  install_package "apt-utils"
  ;;
fedora)
  install_package "python3-libdnf5"
  ;;
esac

uv sync
uv run pre-commit install

if [ "$platform" = "debian" ]; then
  uv pip install six python-debian
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
