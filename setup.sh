#!/bin/sh

# Helper function to show usage information
show_help() {
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
ansible_args=""

# Process arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      show_help
      exit 0
      ;;
    --skip-lint)
      skip_lint=true
      ;;
    --only-lint)
      lint_only=true
      ;;
    *)
      ansible_args="$ansible_args $1"
      ;;
  esac
  shift
done

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
script_dir=$(cd "$(dirname "$0")" && pwd)
repo="$script_dir"

if [ "$skip_lint" = false ]; then
  # Validate Ansible playbooks and roles with ansible-lint
  echo "Validating Ansible playbooks and roles with ansible-lint..."
  if ! ansible-lint "$repo/playbook.yml"; then
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

# Handle git variables
if command -v git >/dev/null 2>&1; then
  git_name=$(git config --global user.name)
  git_email=$(git config --global user.email)
  
  if [ -n "$git_name" ] && [ -n "$git_email" ]; then
    extra_vars="{\"git_user_name\":\"$git_name\",\"git_user_email\":\"$git_email\"}"
    extra_args="$extra_args --extra-vars '$extra_vars'"
  fi
fi

# Run the Ansible playbook
cd "$repo" && ANSIBLE_CONFIG="$repo/ansible.cfg" eval "ansible-playbook $extra_args '$repo/playbook.yml' $ansible_args"
