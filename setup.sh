#!/bin/bash

# Helper function to show usage information
function show_help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

This script ensures Ansible is installed, sets up the environment, and runs the Ansible playbook located in the same directory.

Before running the playbook, it will also install 'ansible-lint' and validate all Ansible playbooks and roles.

Options passed to this script are forwarded to the 'ansible-playbook' command.

Common OPTIONS:
  --help              Show this help message and exit.
  --list-tasks        List all tasks in the playbook without executing anything.
  --list-hosts        List all hosts that the playbook will target.
  --only-lint         Will only run the linting process and exit.
  --skip-lint         Skip linting before running playbook
  -v                  Enable verbose mode (can use -vvv for more verbosity).

Examples:
  Run the playbook normally:
    $(basename "$0")

  List all tasks in the playbook:
    $(basename "$0") --list-tasks
EOF
}

skip_lint=false
lint_only=false
declare -a ansible_args=()
for arg in "$@"; do
  if [[ "$arg" == "--help" ]]; then
    show_help
    exit 0
  elif [[ "$arg" == "--skip-lint" ]]; then
    skip_lint=true
  elif [[ "$arg" == "--only-lint" ]]; then
    lint_only=true
  else
    ansible_args+=("$arg")
  fi
done
set -- "${ansible_args[@]}"  # Replace original args with filtered args

# Ensure Ansible is installed
if ! command -v ansible >/dev/null 2>&1; then
  echo "Ansible not found. Installing..."
  sudo apt update
  sudo apt install -y software-properties-common
  sudo apt-add-repository -y ppa:ansible/ansible
  sudo apt update
  sudo apt install -y ansible
fi

# Ensure ansible-lint is installed
if ! command -v ansible-lint >/dev/null 2>&1; then
  echo "ansible-lint not found. Installing..."
  sudo apt install -y ansible-lint
fi

# Create directories for caching and retry files
mkdir -p ~/.ansible/cache
mkdir -p ~/.ansible/fact_cache
mkdir -p ~/.ansible/retry_files

# Navigate to the directory containing this script
pushd "$(dirname "$0")" > /dev/null || exit
repo=$(pwd)
popd > /dev/null || exit

if [ "$skip_lint" = false ]; then
  # Validate Ansible playbooks and roles with ansible-lint
  echo "Validating Ansible playbooks and roles with ansible-lint..."
  ansible-lint "$repo/playbook.yml"
  if [[ $? -ne 0 ]]; then
    echo "Ansible linting failed. Please fix the errors above and try again."
    exit 1
  fi
  if [ "$lint_only" = true ]; then
    exit 0
  fi
fi

# Check if we can run sudo without prompting for a password
if sudo -n true 2>/dev/null; then
  extra_args=""
else
  extra_args="--ask-become-pass"
fi

declare -a vars=()

if command -v git >/dev/null 2>&1; then
  git_name=$(git config --global user.name)
  git_email=$(git config --global user.email)

  if [[ -n "${git_name}" ]]; then
    vars+=("\"git_user_name\":\"${git_name}\"")
  fi

  if [[ -n "${git_email}" ]]; then
    vars+=("\"git_user_email\":\"${git_email}\"")
  fi
fi

# Convert array to JSON object and handle as a single argument
if [ ${#vars[@]} -ne 0 ]; then
  extra_args="${extra_args:+$extra_args }--extra-vars '{$(IFS=,; echo "${vars[*]}")}'"
fi

# Run the Ansible playbook with any additional arguments passed to this script
eval "cd '${repo}'; ANSIBLE_CONFIG='${repo}/ansible.cfg' ansible-playbook ${extra_args} '${repo}/playbook.yml' $*"
