#!/bin/sh

show_help() {
  cat <<EOF
Usage: $(basename "$0") [PLAYBOOK] [OPTIONS]

This script ensures Ansible is installed, sets up the environment, and runs an Ansible playbook from the playbooks/ directory.

Before running the playbook, it will also install 'ansible-lint' and validate all Ansible playbooks and roles.

If no PLAYBOOK is specified, a list of available playbooks will be shown.

Options passed to this script are forwarded to the 'ansible-playbook' command.

Common OPTIONS:
  --help                Show this help message and exit.
  --list-tasks          List all tasks in the playbook without executing anything.
  -v                    Enable verbose mode (can use -vvv for more verbosity).

Examples:
  List available playbooks:
    $(basename "$0")

  Run a specific playbook:
    $(basename "$0") harden_fedora

  List all tasks in a specific playbook:
    $(basename "$0") harden_fedora --list-tasks
EOF
}

process_arguments() {
  playbook=""

  # First argument is the playbook name if it doesn't start with a dash
  if [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; then
    playbook="$1"
    shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
    --help)
      show_help
      exit 0
      ;;
    -v|-vv*)
      ansible_args="$ansible_args $1"
      ;;
    *)
      ansible_args="$ansible_args $1"
      ;;
    esac
    shift
  done
}

detect_platform() {
  platform="unknown"
  case "$(uname -s)" in
    Darwin)
      platform="macos"
      ;;
    Linux)
      if command -v apt >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
        platform="debian"
      elif command -v dnf >/dev/null 2>&1; then
        platform="fedora"
      else
        platform="linux"
      fi
      ;;
  esac
  echo "$platform"
}

PLATFORM=$(detect_platform)

check_sudo_access() {
  if ! sudo -n true 2>/dev/null; then
    echo " --ask-become-pass"
  fi
}

main() {
  ansible_args=""

  playbook=""

  process_arguments "$@"

  script_dir="$(cd "$(dirname "$0")" && pwd)"
  cd "$script_dir" || { echo "Error repo: $script_dir not found" && exit 1; }

  if [ ! -d "$script_dir/playbooks" ]; then
    echo "Error: Playbooks directory not found at $script_dir/playbooks"
    exit 1
  fi

  if [ -z "$playbook" ]; then
    echo "Available playbooks:"
    ls -1 "$script_dir/playbooks/" | grep .yml | sort | while read -r file; do
      basename=$file
      file="$script_dir/playbooks/$file"
      name=$(echo "$basename" | cut -d'.' -f1 || echo "")
      description=$(grep -m 1 '^- name:' "$file" | cut -d' ' -f3- || echo "")
      if [ -z "$description" ]; then
        description="$name"
      fi
      printf "  %-20s %s\n" "$name" "$description"
    done
    exit 0
  fi

  playbook_path="$script_dir/playbooks/${playbook}.yml"
  if [ ! -f "$playbook_path" ]; then
    echo "Error: Playbook '$playbook' not found at $playbook_path"
    echo "Run '$(basename "$0")' without arguments to see available playbooks"
    exit 1
  fi

  . .venv/bin/activate || {
    echo "Unable to activate virtual environment."
    exit 1
  }

  extra_args="$(check_sudo_access) --extra-vars real_user=$(id -un) --extra-vars real_uid=$(id -u) --extra-vars real_gid=$(id -g)"
  ANSIBLE_CONFIG=ansible.cfg ansible-playbook $extra_args "$playbook_path" $ansible_args
}

main "$@"
