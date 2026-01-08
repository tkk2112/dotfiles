#!/bin/sh
# shellcheck shell=dash
if [ "${DOTFILES_DEBUG:-}" = "1" ]; then
    set -x
fi
script_dir=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(realpath "$script_dir/..")

cd "$repo_dir" || {
    printf 'Failed to change directory to %s\n' "$repo_dir" >&2
    exit 1
}

if ! printenv DOTFILES_CI >/dev/null; then
    export DOTFILES_UPDATE_UV_QUIET=1
    . "${script_dir}/install_uv.sh"
fi

export UV_PROJECT="${repo_dir}"
export UV_WORKING_DIRECTORY="${repo_dir}"
export UV_FROZEN=1

export ANSIBLE_COLLECTIONS_PATH="${repo_dir}/.config/collections"
export ANSIBLE_CONFIG="${repo_dir}/ansible.cfg"
export ANSIBLE_LIBRARY="${repo_dir}/library"
export ANSIBLE_MODULE_UTILS="${repo_dir}/.config/plugins/module_utils"
export ANSIBLE_ROLES_PATH="${repo_dir}/roles"

uv run ansible-galaxy collection install --requirements-file requirements.yml --upgrade

# shellcheck disable=SC2068
uv run ansible-lint --project-dir="${repo_dir}" site.yml $@
