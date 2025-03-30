#!/bin/sh

show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script ensures Ansible is installed, sets up the environment, and runs the Ansible playbook located in the same directory.

Before running the playbook, it will also install 'ansible-lint' and validate all Ansible playbooks and roles.

Options passed to this script are forwarded to the 'ansible-playbook' command.

Common OPTIONS:
  --help                Show this help message and exit.
  --list-tasks          List all tasks in the playbook without executing anything.
  --list-hosts          List all hosts that the playbook will target.
  --only-lint           Will only run the linting process and exit.
  --skip-lint           Skip linting before running playbook
  --skip-dirty-prompt   Skip prompt about dirty git repository
  -v                    Enable verbose mode (can use -vvv for more verbosity).

Examples:
  Run the playbook normally:
    $(basename "$0")

  List all tasks in the playbook:
    $(basename "$0") --list-tasks
EOF
}

# "flags"
apt_updated=3
skip_lint=4
only_lint=5
skip_dirty=6

set_flag() {
  [ -n "$1" ] && eval "exec $1>&1"
}

unset_flag() {
  [ -n "$1" ] && eval "exec $1>&-"
}

has_flag() {
  [ -n "$1" ] && [ -e "/dev/fd/$1" ]
}

check_sudo_access() {
  if ! sudo -n true 2>/dev/null; then
    echo " --ask-become-pass"
  fi
}

process_arguments() {
  while [ $# -gt 0 ]; do
    case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --skip-lint)
      set_flag $skip_lint
      ;;
    --only-lint)
      set_flag $only_lint
      ;;
    --skip-dirty-prompt)
      set_flag $skip_dirty
      ;;
    -v|-vv*)
      ansible_args="$ansible_args $1"
      linter_args="$linter_args $1"
      ;;

    --fix|--fix=*)
      linter_args="$linter_args $1"
      ;;
    *)
      ansible_args="$ansible_args $1"
      ;;
    esac
    shift
  done
}

ensure_apt_updated() {
  if ! has_flag $apt_updated; then
      sudo DEBIAN_FRONTEND=noninteractive apt -qq update </dev/null >/dev/null
    set_flag $apt_updated
  fi
}

install_package() {
  package="$1"
    if ! dpkg -s "$package" >/dev/null 2>&1; then
    echo "Installing $package..."
    ensure_apt_updated
      sudo DEBIAN_FRONTEND=noninteractive apt -qq install -y "$package" </dev/null >/dev/null
  fi
}

install_bin_package() {
  package="$1"
  binary="${2:-$1}" # Use first argument as binary name if second is not provided

  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "$binary not found. "
    install_package "$package"
  fi
}

install_or_update_uv() {
  if ! command -v ~/.local/bin/uv >/dev/null 2>&1; then
    echo "Installing 'uv'..."
    curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
  else
    echo "Updating 'uv'..."
    ~/.local/bin/uv self update
  fi
}

create_ansible_directories() {
  mkdir -p .config/cache
  mkdir -p .config/fact_cache
  mkdir -p .config/retry_files
}

run_ansible_linter() {
  repo="$1"
  shift
  lint_args="$*"
  echo "Validating Ansible playbooks and roles with ansible-lint..."
  cd "$repo" || {
    echo "Failed to change directory to $repo"
    exit 1
  }

  # shellcheck disable=SC2086
  if ! ~/.local/bin/uv run ansible-lint --nocolor --project-dir="$repo" ${lint_args} playbook.yml; then
    echo "Ansible linting failed. Please fix the errors above and try again."
    exit 1
  fi
}

update_git_repo() {
  # Only run in if DOTFILES_LOCATION is not set
  if [ -z "${DOTFILES_LOCATION}" ]; then
    git remote -v | grep push | grep -q https && git remote set-url --push origin git@github.com:tkk2112/dotfiles.git
    [ "$(git config user.email)" = "thomas@sl.m04r.space" ] || git config user.email "thomas@sl.m04r.space"

    # Check if repository has any changes
    if [ -z "$(git status --porcelain)" ]; then
      echo "Repository is clean, pulling updates with rebase..."
      git rebase origin/main || {
        echo "Failed to pull updates."
        exit 1
      }
    else
      echo "Repository has local changes, cannot pull updates automatically."
      echo "Changes in repository:"
      git status --porcelain
      if ! has_flag $skip_dirty; then
        echo "Press Enter to continue or Ctrl+C to abort..."
        read -r _
      else
        echo "Skipping prompt due to --skip-dirty-prompt flag."
      fi
    fi
  fi
}

determine_repo() {
  if [ -n "${DOTFILES_LOCATION}" ]; then
    if [ -f "${DOTFILES_LOCATION}/setup.sh" ]; then
      repo="${DOTFILES_LOCATION}"
    else
      echo "Error: ${DOTFILES_LOCATION}/setup.sh does not exist" 1>&2
      exit 1
    fi
  elif ! cd "$script_dir" >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    target_dir="${HOME}/.dotfiles"
    target_repo="https://github.com/tkk2112/dotfiles.git"
    echo "Not in a git repository. Cloning $target_repo to $target_dir..." 1>&2
    if [ ! -d "$target_dir" ]; then
      git clone "$target_repo" "$target_dir"
    fi
    repo="$target_dir"
  else
    repo="$script_dir"
  fi
  echo "$repo"
}

main() {
  ansible_args=""
  linter_args=""
  process_arguments "$@"

    install_package "apt-utils"
  install_bin_package "git"

  install_or_update_uv

  script_dir="$(cd "$(dirname "$0")" && pwd)"
  repo="$(determine_repo)"

  cd "$repo" || { echo "Error repo: $repo not found" && exit 1; }

  if [ -z "${DOTFILES_LOCATION}" ]; then
    update_git_repo
  fi

  ~/.local/bin/uv sync --link-mode=copy
  ~/.local/bin/uv run pre-commit install

  create_ansible_directories

  collections="community.general"
  echo "Installing Ansible collections..."
  for collection in $collections; do
    echo "  - $collection"
    ~/.local/bin/uv run ansible-galaxy collection install "$collection" --upgrade
  done

  if ! has_flag $skip_lint; then
    run_ansible_linter "$repo" "$linter_args"

    if has_flag $only_lint; then
      exit 0
    fi
  fi

  extra_args="$(check_sudo_access)"

  ANSIBLE_CONFIG=ansible.cfg eval "$HOME/.local/bin/uv run ansible-playbook $extra_args ./playbook.yml $ansible_args"
}

main "$@"
